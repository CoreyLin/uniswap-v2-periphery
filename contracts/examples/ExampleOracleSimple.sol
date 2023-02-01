pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/UniswapV2OracleLibrary.sol';
import '../libraries/UniswapV2Library.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract ExampleOracleSimple {
    using FixedPoint for *; // *这种语法注意一下，值得学习

    uint public constant PERIOD = 24 hours; // 一个周期是24小时

    IUniswapV2Pair immutable pair; // 取哪个pair的价格
    address public immutable token0; // pair的token0地址
    address public immutable token1; // pair的token1地址

    uint    public price0CumulativeLast;
    uint    public price1CumulativeLast;
    uint32  public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average; // token0的平均价格，注意是一个public方法
    FixedPoint.uq112x112 public price1Average; // token1的平均价格，注意是一个public方法

    constructor(address factory, address tokenA, address tokenB) public {
        // 根据tokenA,tokenB找到对应的pair，然后初始化IUniswapV2Pair合约
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        // 得到当前accumulated price value (1 / 0)
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        // 得到当前accumulated price value (0 / 1)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        // 得到当前reserve0, reserve1以及最近一次更新accumulated price的区块的时间戳
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'ExampleOracleSimple: NO_RESERVES'); // ensure that there's liquidity in the pair
    }

    function update() external {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        // 当前区块时间戳离上次blockTimestampLast的时间差，注意，本方法的最后一行代码会把当前时间戳又设置为blockTimestampLast，即更新blockTimestampLast
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        // 时间流逝必须超过至少一个周期，即24小时
        require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        // 计算价格
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        // 更新状态变量
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'ExampleOracleSimple: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
