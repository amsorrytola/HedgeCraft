// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HedgingMath.sol";
import "./UniswapLPProvider.sol";
import "./AaveLeverage.sol";
import "./UniswapSwapper.sol";

/**
 * @title PolygonHedge
 * @notice Main protocol contract orchestrating LP + hedge positions
 * @dev Combines Uniswap V3 LP with Aave shorts for IL protection
 */
contract PolygonHedge is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    UniswapLPProvider public lpProvider;
    AaveLeverage public leverage;
    UniswapSwapper public swapper;
    HedgingMath public hedgingMath;

    // Hedged position tracking
    struct HedgedPosition {
        uint256 lpTokenId; // Uniswap LP NFT ID
        uint256 hedgePositionId; // Aave short position ID
        address token0;
        address token1;
        uint128 lpLiquidity;
        uint256 lpAmount0;
        uint256 lpAmount1;
        uint256 hedgeAmount;
        uint256 initialPrice0;
        uint256 initialPrice1;
        bool isActive;
    }

    mapping(address => mapping(uint256 => HedgedPosition)) public hedgedPositions;
    mapping(address => uint256) public hedgePositionCount;
    mapping(address => uint256[]) public userHedgeIds;

    // Configuration
    uint256 public lpAllocationPercent = 79; // 79% to LP, 21% to hedge
    uint256 public minDepositAmount = 1e6; // Minimum 1 USDC equivalent

    event HedgedPositionOpened(
        address indexed user,
        uint256 indexed hedgeId,
        uint256 lpTokenId,
        uint256 hedgePositionId,
        uint256 lpValue,
        uint256 hedgeValue
    );

    event HedgedPositionClosed(
        address indexed user,
        uint256 indexed hedgeId,
        uint256 lpTokenId,
        uint256 hedgePositionId,
        uint256 totalValue
    );

    event AllocationUpdated(uint256 newLpPercent);
    event MinDepositUpdated(uint256 newMinDeposit);

    error InvalidInput();
    error InsufficientDeposit();
    error PositionNotFound();
    error OnlyPositionOwner();

    constructor(
        address _lpProvider,
        address _leverage,
        address _swapper,
        address _hedgingMath
    ) {
        require(
            _lpProvider != address(0) &&
            _leverage != address(0) &&
            _swapper != address(0) &&
            _hedgingMath != address(0),
            "Invalid addresses"
        );

        lpProvider = UniswapLPProvider(_lpProvider);
        leverage = AaveLeverage(_leverage);
        swapper = UniswapSwapper(_swapper);
        hedgingMath = HedgingMath(_hedgingMath);
    }

    /**
     * @notice Open hedged LP position (79% LP + 21% short)
     * @param token0 First token in pair
     * @param token1 Second token in pair
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @param tickLower Lower tick for LP range
     * @param tickUpper Upper tick for LP range
     * @return hedgeId Position ID for tracking
     */
    function openHedgedPosition(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external nonReentrant returns (uint256 hedgeId) {
        require(token0 != address(0) && token1 != address(0), "Invalid tokens");
        require(amount0 > 0 && amount1 > 0, "Amounts must be > 0");
        
        uint256 totalValue = amount0 + amount1; // Simplified valuation
        require(totalValue >= minDepositAmount, "Deposit too small");

        // Transfer tokens from user
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        // Calculate allocation: 79% LP, 21% hedge
        uint256 lpAmount0 = (amount0 * lpAllocationPercent) / 100;
        uint256 lpAmount1 = (amount1 * lpAllocationPercent) / 100;
        uint256 hedgeAmount0 = amount0 - lpAmount0;
        uint256 hedgeAmount1 = amount1 - lpAmount1;

        // Approve LP provider
        IERC20(token0).safeApprove(address(lpProvider), lpAmount0);
        IERC20(token1).safeApprove(address(lpProvider), lpAmount1);

        // Create LP position
        (uint256 lpTokenId, uint128 lpLiquidity, uint256 usedAmount0, uint256 usedAmount1) =
            lpProvider.createLPPosition(token0, token1, lpAmount0, lpAmount1, tickLower, tickUpper);

        // Create hedge position with remaining tokens
        uint256 leveragePositionId = 0;
        
        // Approve leverage for hedge
        if (hedgeAmount0 > 0) {
            IERC20(token0).safeApprove(address(leverage), hedgeAmount0);
        }
        if (hedgeAmount1 > 0) {
            IERC20(token1).safeApprove(address(leverage), hedgeAmount1);
        }

        // Open short on token1 using token0 as collateral
        IERC20(token0).safeTransfer(address(leverage), hedgeAmount0);
        leveragePositionId = leverage.openShortPosition(
            token0,
            token1,
            hedgeAmount0,
            1.25e18 // 1.25x leverage
        );

        // Store hedge position
        hedgeId = hedgePositionCount[msg.sender]++;
        userHedgeIds[msg.sender].push(hedgeId);

        hedgedPositions[msg.sender][hedgeId] = HedgedPosition({
            lpTokenId: lpTokenId,
            hedgePositionId: leveragePositionId,
            token0: token0,
            token1: token1,
            lpLiquidity: lpLiquidity,
            lpAmount0: usedAmount0,
            lpAmount1: usedAmount1,
            hedgeAmount: hedgeAmount0 + hedgeAmount1,
            initialPrice0: 1e18, // Placeholder
            initialPrice1: 1e18, // Placeholder
            isActive: true
        });

        emit HedgedPositionOpened(
            msg.sender,
            hedgeId,
            lpTokenId,
            leveragePositionId,
            usedAmount0 + usedAmount1,
            hedgeAmount0 + hedgeAmount1
        );

        return hedgeId;
    }

    /**
     * @notice Close hedged position and withdraw all tokens
     * @param hedgeId Position ID to close
     */
    function closeHedgedPosition(uint256 hedgeId) external nonReentrant {
        HedgedPosition storage position = hedgedPositions[msg.sender][hedgeId];
        require(position.isActive, "Position not active");

        // Close LP position
        (uint256 lpAmount0, uint256 lpAmount1) = lpProvider.decreaseLiquidity(
            position.lpTokenId,
            position.lpLiquidity
        );

        // Close hedge position
        leverage.closeShortPosition(position.hedgePositionId);

        position.isActive = false;

        emit HedgedPositionClosed(
            msg.sender,
            hedgeId,
            position.lpTokenId,
            position.hedgePositionId,
            lpAmount0 + lpAmount1
        );
    }

    /**
     * @notice Collect fees from LP position
     * @param hedgeId Position ID
     */
    function collectFees(uint256 hedgeId) external nonReentrant {
        HedgedPosition storage position = hedgedPositions[msg.sender][hedgeId];
        require(position.isActive, "Position not active");

        lpProvider.collectFees(position.lpTokenId);
    }

    /**
     * @notice Get hedged position details
     * @param user User address
     * @param hedgeId Position ID
     * @return position Hedged position struct
     */
    function getHedgedPosition(address user, uint256 hedgeId)
        external
        view
        returns (HedgedPosition memory position)
    {
        return hedgedPositions[user][hedgeId];
    }

    /**
     * @notice Get all hedge positions for user
     * @param user User address
     * @return positions Array of position IDs
     */
    function getUserHedgePositions(address user)
        external
        view
        returns (uint256[] memory)
    {
        return userHedgeIds[user];
    }

    /**
     * @notice Update LP allocation percentage
     * @param newPercent New LP allocation percentage (e.g., 79)
     */
    function setLpAllocationPercent(uint256 newPercent) external onlyOwner {
        require(newPercent > 0 && newPercent < 100, "Invalid percentage");
        lpAllocationPercent = newPercent;
        emit AllocationUpdated(newPercent);
    }

    /**
     * @notice Update minimum deposit amount
     * @param newMinDeposit New minimum deposit
     */
    function setMinDepositAmount(uint256 newMinDeposit) external onlyOwner {
        minDepositAmount = newMinDeposit;
        emit MinDepositUpdated(newMinDeposit);
    }

    /**
     * @notice Emergency token recovery
     * @param token Token to recover
     */
    function recoverToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(msg.sender, balance);
        }
    }
}
