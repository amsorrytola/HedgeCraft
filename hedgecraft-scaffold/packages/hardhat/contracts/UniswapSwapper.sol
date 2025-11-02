// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title UniswapSwapper
 * @notice Handles token swaps on Uniswap V3 for PolygonHedge
 * @dev Integrates with Uniswap V3 SwapRouter for efficient token exchanges
 */

interface ISwapRouter {
    struct ExactInputSingleParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) 
        external payable 
        returns (uint256 amountOut);
}

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) 
        external view 
        returns (address pool);
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    
    function fee() external view returns (uint24);
}

contract UniswapSwapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;
    IUniswapV3Factory public immutable factory;
    address public immutable WMATIC;

    uint24 public constant DEFAULT_FEE = 3000; // 0.3%
    uint256 public constant SLIPPAGE_TOLERANCE = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10000;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    error InvalidSwapParams();
    error InsufficientAmountOut();
    error SwapFailed();

    constructor(
        address _swapRouter,
        address _quoter,
        address _factory,
        address _wmatic
    ) {
        require(_swapRouter != address(0), "Invalid router");
        require(_quoter != address(0), "Invalid quoter");
        require(_factory != address(0), "Invalid factory");
        require(_wmatic != address(0), "Invalid WMATIC");

        swapRouter = ISwapRouter(_swapRouter);
        quoter = IQuoter(_quoter);
        factory = IUniswapV3Factory(_factory);
        WMATIC = _wmatic;
    }

    /**
     * @notice Swap exact amount of input token for output token
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token
     * @return amountOut Amount of output token received
     */
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public nonReentrant returns (uint256 amountOut) {
        if (tokenIn == address(0) || tokenOut == address(0) || amountIn == 0) {
            revert InvalidSwapParams();
        }

        // Get expected output amount
        uint256 minAmountOut = _getExpectedAmountOut(tokenIn, tokenOut, amountIn);

        // Apply slippage tolerance
        uint256 amountOutMinimum = (minAmountOut * (BASIS_POINTS - SLIPPAGE_TOLERANCE)) / BASIS_POINTS;

        // Transfer tokens from sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve router
        IERC20(tokenIn).safeApprove(address(swapRouter), amountIn);

        // Execute swap
        bytes memory path = abi.encodePacked(tokenIn, DEFAULT_FEE, tokenOut);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        try swapRouter.exactInputSingle(params) returns (uint256 amount) {
            amountOut = amount;
        } catch {
            revert SwapFailed();
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }

    /**
     * @notice Internal swap for contract use
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @return amountOut Amount received
     */
    function _swapInternal(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        uint256 minAmountOut = _getExpectedAmountOut(tokenIn, tokenOut, amountIn);
        uint256 amountOutMinimum = (minAmountOut * (BASIS_POINTS - SLIPPAGE_TOLERANCE)) / BASIS_POINTS;

        IERC20(tokenIn).safeApprove(address(swapRouter), amountIn);

        bytes memory path = abi.encodePacked(tokenIn, DEFAULT_FEE, tokenOut);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        try swapRouter.exactInputSingle(params) returns (uint256 amount) {
            amountOut = amount;
        } catch {
            revert SwapFailed();
        }

        return amountOut;
    }

    /**
     * @notice Get expected output amount for a swap
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function _getExpectedAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        try quoter.quoteExactInputSingle(
            tokenIn,
            tokenOut,
            DEFAULT_FEE,
            amountIn,
            0
        ) returns (uint256 amount) {
            amountOut = amount;
        } catch {
            amountOut = amountIn; // Fallback
        }
        return amountOut;
    }

    /**
     * @notice Get current price of token pair
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @return price Current price in WAD format
     */
    function getPrice(address tokenIn, address tokenOut) 
        external view 
        returns (uint256 price) 
    {
        address pool = factory.getPool(tokenIn, tokenOut, DEFAULT_FEE);
        require(pool != address(0), "Pool does not exist");

        IUniswapV3Pool poolContract = IUniswapV3Pool(pool);
        (uint160 sqrtPriceX96, , , , , , ) = poolContract.slot0();

        // Convert sqrtPriceX96 to price
        uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        price = (priceX192 * 1e18) >> 192;

        return price;
    }

    /**
     * @notice Recover stuck tokens
     * @param token Token to recover
     * @param to Recipient address
     */
    function recoverToken(address token, address to) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }
}