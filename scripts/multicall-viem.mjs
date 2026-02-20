import fs from 'node:fs'
import { createPublicClient, http, parseAbi } from 'viem'
import * as viemChains from 'viem/chains'

const [, , callsFile] = process.argv
const network = process.env.NETWORK || 'base'
const rpcUrl = process.env.RPC_URL

if (!callsFile || !rpcUrl) {
  console.error(JSON.stringify({
    error: 'Usage: multicall-viem.mjs <calls.json> with NETWORK and RPC_URL env vars'
  }))
  process.exit(1)
}

const chainKey = network === 'ethereum' ? 'mainnet' : network
const chain = viemChains[chainKey]

const client = chain
  ? createPublicClient({ chain, transport: http(rpcUrl) })
  : createPublicClient({ transport: http(rpcUrl) })

const calls = JSON.parse(fs.readFileSync(callsFile, 'utf8'))

const methodAbi = {
  balanceOf: 'function balanceOf(address owner) view returns (uint256)',
  totalSupply: 'function totalSupply() view returns (uint256)',
  decimals: 'function decimals() view returns (uint8)',
  symbol: 'function symbol() view returns (string)',
  name: 'function name() view returns (string)',
  allowance: 'function allowance(address owner, address spender) view returns (uint256)',
  ownerOf: 'function ownerOf(uint256 tokenId) view returns (address)',
  tokenURI: 'function tokenURI(uint256 tokenId) view returns (string)',
  owner: 'function owner() view returns (address)',
}

const normalize = (value) => {
  if (typeof value === 'bigint') return value.toString()
  if (Array.isArray(value)) return value.map(normalize)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalize(item)]))
  }
  return value
}

const preparedContracts = calls.map((call, idx) => {
  if (!call?.contract || !call?.method) {
    throw new Error(`Invalid call at index ${idx}: expected { contract, method, args? }`)
  }

  const abiDefinition = methodAbi[call.method]
  if (!abiDefinition) {
    throw new Error(`Unsupported method '${call.method}' at index ${idx}`)
  }

  const args = Array.isArray(call.args) ? call.args : []

  if ((call.method === 'ownerOf' || call.method === 'tokenURI') && args.length > 0) {
    args[0] = BigInt(args[0])
  }

  return {
    address: call.contract,
    abi: parseAbi([abiDefinition]),
    functionName: call.method,
    args,
  }
})

try {
  const results = await client.multicall({ contracts: preparedContracts })
  const output = results.map((result, idx) => ({
    contract: calls[idx].contract,
    method: calls[idx].method,
    args: normalize(preparedContracts[idx].args),
    result: result.status === 'success' ? normalize(result.result) : null,
    error: result.status === 'failure' ? result.error.message : null,
  }))

  console.log(JSON.stringify({
    network,
    rpcUrl,
    callCount: calls.length,
    results: output,
  }))
} catch (error) {
  console.error(JSON.stringify({
    error: error instanceof Error ? error.message : String(error),
    network,
    rpcUrl,
  }))
  process.exit(1)
}
