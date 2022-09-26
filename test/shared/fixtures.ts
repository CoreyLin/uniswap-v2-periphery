import { Wallet, Contract } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json'

import ERC20 from '../../build/ERC20.json'
import WETH9 from '../../build/WETH9.json'
import UniswapV1Exchange from '../../build/UniswapV1Exchange.json'
import UniswapV1Factory from '../../build/UniswapV1Factory.json'
import UniswapV2Router01 from '../../build/UniswapV2Router01.json'
import UniswapV2Migrator from '../../build/UniswapV2Migrator.json'
import UniswapV2Router02 from '../../build/UniswapV2Router02.json'
import RouterEventEmitter from '../../build/RouterEventEmitter.json'

const overrides = {
  gasLimit: 9999999
}

interface V2Fixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  WETHPartner: Contract
  factoryV1: Contract
  factoryV2: Contract
  router01: Contract
  router02: Contract
  routerEventEmitter: Contract
  router: Contract
  migrator: Contract
  WETHExchangeV1: Contract
  pair: Contract
  WETHPair: Contract
}

export async function v2Fixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<V2Fixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)]) // 部署tokenA
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)]) // 部署tokenB
  const WETH = await deployContract(wallet, WETH9) // 部署WETH9
  const WETHPartner = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)]) // 部署WETHParter

  // deploy V1
  const factoryV1 = await deployContract(wallet, UniswapV1Factory, []) // 部署v1工厂合约
  await factoryV1.initializeFactory((await deployContract(wallet, UniswapV1Exchange, [])).address) // 初始化v1工厂合约

  // deploy V2
  const factoryV2 = await deployContract(wallet, UniswapV2Factory, [wallet.address]) // 部署工厂合约

  // deploy routers
  const router01 = await deployContract(wallet, UniswapV2Router01, [factoryV2.address, WETH.address], overrides)
  const router02 = await deployContract(wallet, UniswapV2Router02, [factoryV2.address, WETH.address], overrides) // 部署router02, 参数为工厂合约地址、WETH9合约地址

  // event emitter for testing
  const routerEventEmitter = await deployContract(wallet, RouterEventEmitter, [])

  // deploy migrator
  const migrator = await deployContract(wallet, UniswapV2Migrator, [factoryV1.address, router01.address], overrides) // 部署迁移合约，用于v1到v2的迁移

  // initialize V1
  await factoryV1.createExchange(WETHPartner.address, overrides)
  const WETHExchangeV1Address = await factoryV1.getExchange(WETHPartner.address)
  const WETHExchangeV1 = new Contract(WETHExchangeV1Address, JSON.stringify(UniswapV1Exchange.abi), provider).connect(
    wallet
  )

  // initialize V2
  await factoryV2.createPair(tokenA.address, tokenB.address) // 创建pair
  const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address) // 获取pair地址
  const pair = new Contract(pairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet) // 获取pair合约对象

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  await factoryV2.createPair(WETH.address, WETHPartner.address) // 创建pair，参数是一个特殊的合约，WETH9
  const WETHPairAddress = await factoryV2.getPair(WETH.address, WETHPartner.address) // 获取pair地址
  const WETHPair = new Contract(WETHPairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet) // 获取pair合约对象

  return {
    token0,
    token1,
    WETH,
    WETHPartner,
    factoryV1,
    factoryV2,
    router01,
    router02,
    router: router02, // the default router, 01 had a minor bug
    routerEventEmitter,
    migrator,
    WETHExchangeV1,
    pair,
    WETHPair
  }
}
