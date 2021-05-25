pragma solidity >=0.6.2;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    /*
    向ERC-20⇄ERC-20 pair/pool中增加流动性。
    - 为了覆盖所有可能的场景，msg.sender应该已经在tokenA/tokenB上给了router一个至少amountADesired/amountBDesired的allowance值。
      可以事先调用tokenA和tokenB的approve函数以给router分配资金处置额度。
    - 总是根据交易执行时的价格（tokenA和tokenB的比率），以理想的比率增加流动性。
    - 如果tokenA/tokenB的pair/pool不存在，则会自动创建一个，并添加刚刚amountADesired/amountBDesired tokens的流动性。
    参数解释：
    - tokenA: tokenA ERC20合约的地址
    - tokenB: tokenB ERC20合约的地址
    - amountADesired: 如果B/A的价格 <= amountBDesired/amountADesired (A贬值)，作为流动性添加的代币A的数量。打个比方，
      在确定参数amountADesired和amountBDesired的时候，B/A=3，于是amountBDesired设置为3，amountADesired设置为1，然而在交易真正执行的时候，
      B/A的值变成了2，即A贬值了，那么不能把amountBDesired设置为3，因为需要1.5 A，所以只能把amountADesired设置为1，需要2个B。
      至于这种价格变动是否能够接受，即需要的B从3变成2是否可以接受，就取决于另一个参数amountBMin，如果amountBMin设置为<=2，
      那么就会以B=2,A=1增加流动性，此时amountBDesired就不起作用了。
    - amountBDesired：同上
    - amountAMin：在交易回滚之前，B/A价格可以上升的范围。值必须<=amountADesired。
    - amountBMin：在交易回滚之前，A/B价格可以上升的范围。值必须<=amountBDesired。
    - to: liquidity tokens也就是UNI tokens的接收者，通常是msg.sender本人的地址，但也可以指定其他受益人。
    - deadline: Unix时间戳，在此之后交易将回滚，注意，以太坊中单位是秒，FISCO中单位是毫秒。
    返回值解释：
    - amountA: 最终确定的注入的A的流动性，也就是msg.sender转给pair的tokenA的数量
    - amountB: 同上
    - liquidity: 为to地址(通常就是msg.sender)铸造的liquidity tokens的数量，也就是注入流动性获得的权益凭证
    */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    /*
    从ERC-20⇄ERC-20 pair/pool中删除流动性。
    msg.sender应该已经在pair/pool中给了router至少liquidity数量的allowance额度，可调用pair的approve函数。
    参数解释：
    - tokenA: tokenA ERC20合约的地址
    - tokenB: tokenB ERC20合约的地址
    - liquidity: 要移除的liquidity tokens的数量
    - amountAMin: 移除liquidity后必须接收的tokenA的最小数量，否则交易回滚。
    - amountBMin: 移除liquidity后必须接收的tokenB的最小数量，否则交易回滚。
    - to: tokenA和tokenB资产的接收地址，通常是msg.sender自己，但也可以指定其他地址作为其受益人，就和买保险一个概念
    - deadline: Unix时间戳，在此之后交易将回滚，注意，以太坊中单位是秒，FISCO中单位是毫秒。
    返回值解释：
    - amountA: 最终收到的tokenA的数量
    - amountB: 最终收到的tokenB的数量
    业务逻辑：会根据交易执行时msg.sender在pool中拥有的liquidity所占的比率，以及A/B的价格，计算出应该收到多少amountA和amountB，
    如果amountA<amountAMin或者amountB<amountBMin，那么交易回滚。
    */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    /*
    从ERC-20⇄ERC-20 pair/pool中删除流动性，但和removeLiquidity不同的是，不需要pre-approval，即msg.sender提前给router approve额度。
    这是依靠IUniswapV2ERC20.sol接口中定义的function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external实现的，
    pair合约也实现了这个函数，因为pair合约也是一种ERC20合约，且实现了IUniswapV2ERC20接口。
    参数解释：
    - tokenA: tokenA ERC20合约的地址
    - tokenB: tokenB ERC20合约的地址
    - liquidity: 要移除的liquidity tokens的数量
    - amountAMin: 移除liquidity后必须接收的tokenA的最小数量，否则交易回滚。
    - amountBMin: 移除liquidity后必须接收的tokenB的最小数量，否则交易回滚。
    - to: tokenA和tokenB资产的接收地址，通常是msg.sender自己，但也可以指定其他地址作为其受益人，就和买保险一个概念
    - deadline: Unix时间戳，在此之后交易将回滚，注意，以太坊中单位是秒，FISCO中单位是毫秒。
    - approveMax: 数字签名中的批准金额是liquidity还是uint(-1)，即最大金额
    - v,r,s: permit签名的组成部分
    返回值解释：
    - amountA: 最终收到的tokenA的数量
    - amountB: 最终收到的tokenB的数量
    业务逻辑：会根据交易执行时msg.sender在pool中拥有的liquidity所占的比率，以及A/B的价格，计算出应该收到多少amountA和amountB，
    如果amountA<amountAMin或者amountB<amountBMin，那么交易回滚。
    */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    /*
    给定一些资产数量和储备(reserves)，返回代表等价价值的另一种资产的数量。
    用于在调用mint之前计算最优token数量。
    */
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    /*
    给定输入资产金额，返回给定储备的另一种资产(计入fees手续费)的最大输出金额。
    用在getAmountsOut中。
    */
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    /*
    给定输入资产数量和一个token地址数组path，通过依次为path中的每对token地址调用getReserves，并使用得到的reserves调用getAmountOut，
    从而计算所有后面的最大输出token数量。
    用于在调用swap之前计算最优token数量。
    例如，amountIn为100，path为[tokenA,tokenB,tokenC]，那么计算的是：
    1.tokenA为100时，用tokenA能兑换多少tokenB
    2.tokenB为100时，用tokenB能兑换多少tokenC
    */
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}
