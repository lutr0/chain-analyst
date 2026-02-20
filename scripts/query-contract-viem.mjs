import { createPublicClient, http, parseAbi } from 'viem'
import * as viemChains from 'viem/chains'

const [, , method, contract, ...rawArgs] = process.argv
const network = process.env.NETWORK || 'base'
const rpcUrl = process.env.RPC_URL

if (!method || !contract || !rpcUrl) {
  console.error(JSON.stringify({
    error: 'Usage: query-contract-viem.mjs <method> <contract> [args...] with NETWORK and RPC_URL env vars'
  }))
  process.exit(1)
}

const chainKey = network === 'ethereum' ? 'mainnet' : network
const chain = viemChains[chainKey]

const client = chain
  ? createPublicClient({ chain, transport: http(rpcUrl) })
  : createPublicClient({ transport: http(rpcUrl) })

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

const argCoercers = {
  ownerOf: (args) => [BigInt(args[0])],
  tokenURI: (args) => [BigInt(args[0])],
}

const abiEntry = methodAbi[method]
if (!abiEntry) {
  console.error(JSON.stringify({
    error: `Unsupported method '${method}' for viem fallback. Use cast with full function signature for custom methods.`,
    method,
    contract,
    args: rawArgs,
  }))
  process.exit(1)
}

const normalize = (value) => {
  if (typeof value === 'bigint') return value.toString()
  if (Array.isArray(value)) return value.map(normalize)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalize(item)]))
  }
  return value
}

try {
  const abi = parseAbi([abiEntry])
  const args = argCoercers[method] ? argCoercers[method](rawArgs) : rawArgs

  const result = await client.readContract({
    address: contract,
    abi,
    functionName: method,
    args,
  })

  console.log(JSON.stringify({
    result: normalize(result),
    method,
    contract,
    args: normalize(args),
    network,
    rpcUrl,
    provider: 'viem',
  }))
} catch (error) {
  console.error(JSON.stringify({
    error: error instanceof Error ? error.message : String(error),
    method,
    contract,
    args: rawArgs,
    network,
    rpcUrl,
    provider: 'viem',
  }))
  process.exit(1)
}
