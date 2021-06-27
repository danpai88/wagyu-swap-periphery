pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

import './libraries/TransferHelper.sol';
import './libraries/WagyuLibrary.sol';
import './interfaces/IWagyuRouter01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWVLX.sol';

contract WagyuRouter01 is IWagyuRouter01 {
    address public immutable override factory;
    address public immutable override WVLX;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'WagyuRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WVLX) public {
        factory = _factory;
        WVLX = _WVLX;
    }

    receive() external payable {
        assert(msg.sender == WVLX); // only accept VLX via fallback from the WVLX contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = WagyuLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = WagyuLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'WagyuRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = WagyuLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'WagyuRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = WagyuLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    function addLiquidityVLX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountVLXMin,
        address to,
        uint deadline
    ) external override payable ensure(deadline) returns (uint amountToken, uint amountVLX, uint liquidity) {
        (amountToken, amountVLX) = _addLiquidity(
            token,
            WVLX,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountVLXMin
        );
        address pair = WagyuLibrary.pairFor(factory, token, WVLX);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWVLX(WVLX).deposit{value: amountVLX}();
        assert(IWVLX(WVLX).transfer(pair, amountVLX));
        liquidity = IUniswapV2Pair(pair).mint(to);
        if (msg.value > amountVLX) TransferHelper.safeTransferVLX(msg.sender, msg.value - amountVLX); // refund dust vlx, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = WagyuLibrary.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = WagyuLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'WagyuRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'WagyuRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityVLX(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountVLXMin,
        address to,
        uint deadline
    ) public override ensure(deadline) returns (uint amountToken, uint amountVLX) {
        (amountToken, amountVLX) = removeLiquidity(
            token,
            WVLX,
            liquidity,
            amountTokenMin,
            amountVLXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWVLX(WVLX).withdraw(amountVLX);
        TransferHelper.safeTransferVLX(to, amountVLX);
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
    ) external override returns (uint amountA, uint amountB) {
        address pair = WagyuLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityVLXWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountVLXMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint amountToken, uint amountVLX) {
        address pair = WagyuLibrary.pairFor(factory, token, WVLX);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountVLX) = removeLiquidityVLX(token, liquidity, amountTokenMin, amountVLXMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = WagyuLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? WagyuLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(WagyuLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = WagyuLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WagyuRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external override ensure(deadline) returns (uint[] memory amounts) {
        amounts = WagyuLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'WagyuRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactVLXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WVLX, 'WagyuRouter: INVALID_PATH');
        amounts = WagyuLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WagyuRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWVLX(WVLX).deposit{value: amounts[0]}();
        assert(IWVLX(WVLX).transfer(WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactVLX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WVLX, 'WagyuRouter: INVALID_PATH');
        amounts = WagyuLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'WagyuRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWVLX(WVLX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferVLX(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForVLX(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WVLX, 'WagyuRouter: INVALID_PATH');
        amounts = WagyuLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WagyuRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWVLX(WVLX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferVLX(to, amounts[amounts.length - 1]);
    }
    function swapVLXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WVLX, 'WagyuRouter: INVALID_PATH');
        amounts = WagyuLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'WagyuRouter: EXCESSIVE_INPUT_AMOUNT');
        IWVLX(WVLX).deposit{value: amounts[0]}();
        assert(IWVLX(WVLX).transfer(WagyuLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferVLX(msg.sender, msg.value - amounts[0]); // refund dust vlx, if any
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure override returns (uint amountB) {
        return WagyuLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure override returns (uint amountOut) {
        return WagyuLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure override returns (uint amountIn) {
        return WagyuLibrary.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view override returns (uint[] memory amounts) {
        return WagyuLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view override returns (uint[] memory amounts) {
        return WagyuLibrary.getAmountsIn(factory, amountOut, path);
    }
}
