// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HedgingMath
 * @notice Mathematical calculations for impermanent loss hedging
 * @dev Provides concentrated liquidity calculations and optimal hedge ratios
 */
contract HedgingMath {
    // Constants for fixed-point math (18 decimals)
    uint256 constant WAD = 1e18;
    uint256 constant PERCENT_100 = 100e18;
    
    // Errors
    error InvalidPriceRange();
    error DivisionByZero();
    error InvalidInput();
    
    /**
     * @notice Calculate liquidity from amounts and price range
     * @dev Uses Uniswap V3 concentrated liquidity formula
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @param sqrtPriceX96 Current sqrt price in Q96 format
     * @param sqrtPriceLowerX96 Lower bound sqrt price
     * @param sqrtPriceUpperX96 Upper bound sqrt price
     * @return liquidity Calculated liquidity
     */
    function calculateLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96
    ) public pure returns (uint128 liquidity) {
        if (sqrtPriceLowerX96 >= sqrtPriceUpperX96) revert InvalidPriceRange();
        if (amount0 == 0 && amount1 == 0) revert InvalidInput();
        
        if (sqrtPriceX96 < sqrtPriceLowerX96) {
            // Only token0 needed
            return uint128(_liquidityFromAmount0(amount0, sqrtPriceLowerX96, sqrtPriceUpperX96));
        } else if (sqrtPriceX96 > sqrtPriceUpperX96) {
            // Only token1 needed
            return uint128(_liquidityFromAmount1(amount1, sqrtPriceLowerX96, sqrtPriceUpperX96));
        } else {
            // Both tokens needed
            uint128 liquidity0 = uint128(_liquidityFromAmount0(amount0, sqrtPriceX96, sqrtPriceUpperX96));
            uint128 liquidity1 = uint128(_liquidityFromAmount1(amount1, sqrtPriceLowerX96, sqrtPriceX96));
            return liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }
    }
    
    /**
     * @notice Calculate optimal hedge ratio (79% LP, 21% short)
     * @param totalValue Total deposit value
     * @return lpAllocation Amount for LP position
     * @return hedgeAllocation Amount for hedge (short) position
     */
    function calculateAllocation(uint256 totalValue) 
        public pure 
        returns (uint256 lpAllocation, uint256 hedgeAllocation) 
    {
        // 79% to LP, 21% to hedge
        lpAllocation = (totalValue * 79) / 100;
        hedgeAllocation = totalValue - lpAllocation;
        return (lpAllocation, hedgeAllocation);
    }
    
    /**
     * @notice Estimate impermanent loss given price change
     * @param initialPrice Initial token price
     * @param currentPrice Current token price
     * @return ilPercent IL as percentage (with 18 decimals)
     */
    function estimateIL(uint256 initialPrice, uint256 currentPrice) 
        public pure 
        returns (uint256 ilPercent) 
    {
        if (initialPrice == 0) revert DivisionByZero();
        
        // IL = 2 * sqrt(priceRatio) / (1 + priceRatio) - 1
        uint256 priceRatio = (currentPrice * WAD) / initialPrice;
        
        // Simplified: IL ≈ ((price_change)^2) / (2 * current_price * initial_price)
        uint256 priceDiff = currentPrice > initialPrice 
            ? currentPrice - initialPrice 
            : initialPrice - currentPrice;
        
        ilPercent = ((priceDiff * priceDiff) * 100) / (2 * currentPrice * initialPrice);
        return ilPercent;
    }
    
    /**
     * @notice Calculate amounts needed for a given liquidity in a price range
     * @param liquidity Target liquidity
     * @param sqrtPriceX96 Current sqrt price
     * @param sqrtPriceLowerX96 Lower tick sqrt price
     * @param sqrtPriceUpperX96 Upper tick sqrt price
     * @return amount0 Amount of token0 needed
     * @return amount1 Amount of token1 needed
     */
    function calculateAmounts(
        uint128 liquidity,
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96
    ) public pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtPriceLowerX96 >= sqrtPriceUpperX96) revert InvalidPriceRange();
        
        if (sqrtPriceX96 <= sqrtPriceLowerX96) {
            amount0 = _getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, liquidity, true);
            amount1 = 0;
        } else if (sqrtPriceX96 >= sqrtPriceUpperX96) {
            amount0 = 0;
            amount1 = _getAmount1Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, liquidity, true);
        } else {
            amount0 = _getAmount0Delta(sqrtPriceX96, sqrtPriceUpperX96, liquidity, true);
            amount1 = _getAmount1Delta(sqrtPriceLowerX96, sqrtPriceX96, liquidity, true);
        }
        
        return (amount0, amount1);
    }
    
    // Internal helper functions
    function _liquidityFromAmount0(
        uint256 amount0,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) internal pure returns (uint256) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        
        uint256 intermediate = (uint256(sqrtPriceBX96) * sqrtPriceAX96) >> 96;
        return (amount0 * intermediate) / (sqrtPriceBX96 - sqrtPriceAX96);
    }
    
    function _liquidityFromAmount1(
        uint256 amount1,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96
    ) internal pure returns (uint256) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        
        return (amount1 << 96) / (sqrtPriceBX96 - sqrtPriceAX96);
    }
    
    function _getAmount0Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        
        uint256 numerator1 = uint256(liquidity) << 96;
        uint256 numerator2 = sqrtPriceBX96 - sqrtPriceAX96;
        
        amount0 = roundUp 
            ? _divRoundingUp(numerator1, numerator2) / sqrtPriceBX96
            : numerator1 / numerator2 / sqrtPriceBX96;
    }
    
    function _getAmount1Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        
        amount1 = roundUp
            ? _mulDivRoundingUp(liquidity, sqrtPriceBX96 - sqrtPriceAX96, 1 << 96)
            : (uint256(liquidity) * (sqrtPriceBX96 - sqrtPriceAX96)) >> 96;
    }
    
    function _divRoundingUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }
    
    function _mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) 
        internal pure 
        returns (uint256 result) 
    {
        result = (a * b) / denominator;
        if ((a * b) % denominator > 0) result++;
    }
}