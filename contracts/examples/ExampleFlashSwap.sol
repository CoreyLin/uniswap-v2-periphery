pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';

import '../libraries/UniswapV2Library.sol';
import '../interfaces/V1/IUniswapV1Factory.sol';
import '../interfaces/V1/IUniswapV1Exchange.sol';
import '../interfaces/IUniswapV2Router01.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';

contract ExampleFlashSwap is IUniswapV2Callee {
    IUniswapV1Factory immutable factoryV1;
    // factory地址
    address immutable factory;
    IWETH immutable WETH;

    // 初始化的参数是factory地址和router地址
    constructor(address _factory, address _factoryV1, address router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        factory = _factory;
        WETH = IWETH(IUniswapV2Router01(router).WETH());
    }

    // needs to accept ETH from any V1 exchange and WETH. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    // gets tokens/WETH via a V2 flash swap, swaps for the ETH/tokens on V1, repays V2, and keeps the rest!
    // 调用者是pair合约
    // 整个闪电贷的过程是：
    // 1.EOA调用v2 pair的swap方法，把to参数设置为ExampleFlashSwap合约的地址
    // 2.ExampleFlashSwap合约借到token了
    // 3.pair合约回调ExampleFlashSwap合约的uniswapV2Call方法，传的sender就是第一步中EOA的地址，即最后收获利润的地址，这一步有几个子步骤：
    // a.ExampleFlashSwap合约去其他地方（比如交易所）进行套利
    // b.还token给pair合约
    // c.把剩下的利润转给EOA
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        address[] memory path = new address[](2);
        uint amountToken;
        uint amountETH;
        { // scope for token{0,1}, avoids stack too deep errors
        // 获取pair合约的token0,token1
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        // 确保调用者确实是pair合约
        assert(msg.sender == UniswapV2Library.pairFor(factory, token0, token1)); // ensure that msg.sender is actually a V2 pair
        // amount0和amount1中至少有一个是0，即不能同时借token0和token1
        assert(amount0 == 0 || amount1 == 0); // this strategy is unidirectional
        // 如果amount0为0,那amount1就为非0,说明借的是amount1，那么path就为[token0,token1]
        path[0] = amount0 == 0 ? token0 : token1;
        path[1] = amount0 == 0 ? token1 : token0;
        // 如果token0是WETH，那么amountToken就是amount1
        amountToken = token0 == address(WETH) ? amount1 : amount0;
        // 如果token0是WETH，那么amountETH就是amount0
        amountETH = token0 == address(WETH) ? amount0 : amount1;
        }

        // 只适合有WETH的pair
        assert(path[0] == address(WETH) || path[1] == address(WETH)); // this strategy only works with a V2 WETH pair
        // 确定非WETH token的地址
        IERC20 token = IERC20(path[0] == address(WETH) ? path[1] : path[0]);
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(address(token))); // get V1 exchange

        if (amountToken > 0) { // 借的是非WETH token
            // 用户设置的在v1套利后要得到的ETH的最小数量，如果最后通过token换取ETH小于这个数，就回滚
            (uint minETH) = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            token.approve(address(exchangeV1), amountToken);
            // 套利的步骤
            // 把借到的token拿到uniswap v1的市场上去swap ETH，得到了amountReceived的ETH
            uint amountReceived = exchangeV1.tokenToEthSwapInput(amountToken, minETH, uint(-1));
            // 要借到这么多数量的token，需要付出多少WETH，这是闪电贷之后需要还的WETH的数量
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountToken, path)[0];
            // 套利得到的ETH数量必须大于要还的WETH数量
            assert(amountReceived > amountRequired); // fail if we didn't get enough ETH back to repay our flash loan
            // 本合约将套利得到的ETH中的一部分（数量为amountRequired）存入WETH，转换为WETH
            WETH.deposit{value: amountRequired}();
            // 还钱操作，借的是token，还的是WETH
            assert(WETH.transfer(msg.sender, amountRequired)); // return WETH to V2 pair
            // 把套利剩下的ETH转给sender，这就是利润，数量为amountReceived - amountRequired
            (bool success,) = sender.call{value: amountReceived - amountRequired}(new bytes(0)); // keep the rest! (ETH)
            // 转账必须成功
            assert(success);
        } else { // 借的是WETH
            (uint minTokens) = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            // 把WETH取出来，就是本合约得到ETH
            WETH.withdraw(amountETH);
            // 套利的步骤
            // 把借到的ETH拿到uniswap v1的市场上去swap token，得到了amountReceived的token
            uint amountReceived = exchangeV1.ethToTokenSwapInput{value: amountETH}(minTokens, uint(-1));
            // 要借到这么多数量的WETH，需要付出多少token，这是闪电贷之后需要还的token的数量
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountETH, path)[0];
            // 套利得到的token数量必须大于要还的token数量
            assert(amountReceived > amountRequired); // fail if we didn't get enough tokens back to repay our flash loan
            // 还钱操作，借的是WETH，还的是token
            assert(token.transfer(msg.sender, amountRequired)); // return tokens to V2 pair
            // 把套利得到的利润发给sender，套利结束
            assert(token.transfer(sender, amountReceived - amountRequired)); // keep the rest! (tokens)
        }
    }
}
