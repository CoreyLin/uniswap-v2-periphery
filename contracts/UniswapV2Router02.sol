pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

/*
上层DApp，即uniswap interface单页面前端程序，通过web3j和metamask等钱包调用UniswapV2Router02与uniswap智能合约交互。
*/
contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;

    /*确保交易执行时没有超时，如果没超时，继续执行，否则回滚*/
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    /*
    factory地址非常重要，因为创建pair，以及根据token的地址获取pair的地址都需要用到factory。
    */
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    /*
    这个函数不会真正执行增加流动性的操作。只负责计算交易执行时应该注入到池中的tokenA和tokenB的数量，并返回。
    */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        /*
        如果没有tokenA和tokenB对应的pair，就由factory创建一个pair。
        */
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        /*
        获取pair的tokenA和tokenB的储备，即pair在tokenA和tokenB中的余额。
        */
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            /*
            如果pair的储备为0，说明还没有注入过流动性，这是第一次注入流动性，那么注入的流动性的数量就刚好是amountADesired, amountBDesired
            */
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            /*
            quote:给定一些资产数量和储备(reserves)，返回代表等价价值的另一种资产的数量，此处得到的amountBOptimal是交易执行时的值，
            可能会和传入的amountBDesired有偏差，因为从交易提交到交易执行会有一段时间，这段时间之内pair内的价格可能发生了变化。
            */
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                /*
                不能注入比amountBDesired还多的tokenB。
                不能注入比amountBMin还少的tokenB。
                总结：注入的tokenB的数量应该在amountBMin和amountBDesired之间。
                */
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                /*
                进入else说明B贬值了。基于amountBDesired计算应该注入的tokenA。
                */
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                /*
                不能注入比amountADesired还多的tokenA。
                */
                assert(amountAOptimal <= amountADesired);
                /*
                不能注入比amountAMin还少的tokenA。
                */
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    /*
    向一个ERC-20⇄ERC-20池中增加流动性。
    - 为了覆盖所有可能的情况，msg.sender应该已经在tokenA/tokenB上给router approve了至少amountADesired/amountBDesired的allowance。
    - 总是根据执行交易时的两种ERC20的价格，以理想的比率增加资产。
    - 如果这两种ERC20 token对应的pair/pool不存在，则会自动创建一个，并添加amountADesired/amountBDesired数量的token。
    参数解释：
    tokenA: 第一个ERC20合约的地址
    tokenB: 第二个ERC20合约的地址
    amountADesired: 如果执行交易时B/A价格<=amountBDesired/amountADesired (A贬值)，作为流动性添加的代币A的数量。
    amountBDesired: 如果执行交易时A/B价格<=amountADesired/amountBDesired (B贬值)，作为流动性添加的代币B的数量。
    amountAMin: 在交易回滚之前，B/A价格可以上升的范围。必须<=amountADesired。
    amountBMin: 在交易回滚之前，A/B价格可以上升的范围。必须<=amountBDesired。
    to: 流动性代币的接收者。
    deadline: Unix时间戳，在此之后交易将回滚。以太坊单位为秒，FISCO单位为毫秒。
    返回值：
    amountA: 发送到池的tokenA的数量。
    amountB: 发送到池的tokenB的数量。
    liquidity: 铸造的pool token的数量。
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
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        /*
        真正应该注入到池中的tokenA和tokenB的数量。
        */
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        /*
        根据factory, tokenA, tokenB地址计算得出确定性的pair的地址。
        */
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        /*
        TransferHelper是uniswap-lib工程中的一个library。
        把amountA的tokenA从用户转给pair。
        把amountB的tokenB从用户转给pair。
        注：此转账是由router合约发起的，所以需要用户提前approve router合约至少amountADesired/amountBDesired的allowance
        */
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        /*
        为to地址mint相应的pool token，代表其在这个资金池的权益。
        */
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    /*
    从ERC20<->ERC20池中移除流动性。
    msg.sender应该已经给router approve了在池中的至少liquidity数量的allowance。
    参数解释：
    tokenA: tokenA的地址。
    tokenB: tokenB的地址。
    liquidity: 要移除的pool token的数量。
    amountAMin: 移除pool token后要收到的tokenA的最小数量，否则交易回滚。
    amountBMin: 移除pool token后要收到的tokenB的最小数量，否则交易回滚。
    to: tokenA和tokenB的接收者。
    deadline: Unix时间戳，在此之后交易将回滚。以太坊单位为秒，FISCO单位为毫秒。
    返回值：
    amountA: 收到的tokenA的数量。
    amountB: 收到的tokenB的数量。
    */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        /*
        根据factory, tokenA, tokenB地址计算得出确定性的pair的地址。
        */
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        /*
        把pair中属于msg.sender的pool token转移liquidity数量给pair。
        IUniswapV2Pair(pair).burn(to)会burn掉pair合约自己拥有的pool token，也就是msg.sender转移给pair合约的pool token。
        所以，每当任意msg.sender在转移pool token给pair地址之前，pair自身拥有的pool token总是为0，转移pool token之后，
        根据pair自己拥有的pool token的数量计算应该接收的tokenA和tokenB的数量，然后转给to地址，同时burn掉pair自己拥有的pool token。
        以上所述的步骤都是一笔交易里的原子操作，不会出现执行一半的情况。
        */
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        /*
        确保收到了指定的最小金额，否则交易回滚。
        */
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        /*通常path的长度是2，第一个元素表示amountIn的token地址，第二个元素表示amountOut的token地址*/
        for (uint i; i < path.length - 1; i++) {
            /*input是向pair注入资金的地址,output是从pair转出资金的地址*/
            (address input, address output) = (path[i], path[i + 1]);
            /*对input和output进行排序，取出其中小的地址*/
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            /*amountOut是要从pair转到to的资金额度*/
            uint amountOut = amounts[i + 1];
            /*
            如果input等于token0，说明是要将pair在token1的金额转给to；反之，说明是要将pair在token0中的金额转给to。
            这么做（包括上面使用UniswapV2Library.sortTokens）的原因是在pair中，token0和token1是经过了排序的，
            token0小于token1，所以在调用pair的函数之前，都需要在调用之前先把token0和token1的顺序排好。
            此处的表达式的结果要么是对token0转出，要么是对token1转出。
            */
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            /*
            swap的逻辑是：1.把一种token从兑换人转给pair合约 2.把另一种token从pair合约转给兑换人
            在UniswapV2Router02.sol的swapExactTokensForTokens函数中，已经完成了“1.把一种token从兑换人转给pair合约”，
            所以此处的swap函数仅完成“2.把另一种token从pair合约转给兑换人”。
            注意：pair中的token0和token1是排好序的，外围的router在调用pair的函数的时候，已经把token A,token B转换成了token0,token1，
            所以在pair的swap中完全不用担心token的顺序的问题，外围的router已经处理好了amount0Out和amount1Out，
            且已经计算好了应该从pair转多少资产给兑换人，所以传进来的值绝对没问题。
            除此以外，在swap中，还通过公式来确保“1.把一种token从兑换人转给pair合约”中转账的数量是足够的，这样才不会导致黑客转一点点amount0In给pair，然后套出大量amount1Out。
            */
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    /*
    在一个pair中，用一种token去兑换另一种token。输入的token的额度确定，输出的token的额度不确定，是动态变化的，需设置自己能接受的最小值。
    打个比方，用5个tokenA，至少要兑换3个tokenB，如果不能换取3个或以上的tokenB，交易就回滚。
    参数解释：
    amountIn: 输入token的金额
    amountOutMin: 输出token的金额的最小值
    path: 通常有2个元素，第一个元素表示输入的token的地址，第二个元素表示输出的token的地址
    to: 表示输出的token的目的地址，即token被转到哪个地址，通常是msg.sender自己，但也可以指定其他受益人
    deadline: 指定超时时间，如果超时之后交易还没执行完，就回滚
    */
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        /*
        对任意数量的pair执行链式getAmountOut计算。通常来说，path只有两个元素（length为2），即tokenA和tokenB的地址。
        计算公式：
        交易前的乘积公式：x*y=K
        交易中的乘积公式：(x+0.997xin)*(y-yout)=K
        */
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        /*
        确保价格的浮动在自己可接受的范围内。
        */
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        /*
        在amountIn所在的token上，router代表msg.sender转账给pair，转账金额是amountIn。
        前提是msg.sender必须在token所在的ERC20合约上approve给router一定转账额度。
        此处可以看出，amountIn的转账是在router中执行的，而不是在pair中执行的。
        */
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    /*
    参考UniswapV2Library.sol的注释。
    */
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
