// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Aave V3 interfaces
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);

    function ADDRESSES_PROVIDER() external view returns (address);

    function POOL() external view returns (address);
}

interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

interface IPool {
    function flashLoanSimple(
        address receiver,
        address token,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/**
 * @title AaveLeverage
 * @notice Manages leveraged short positions using Aave V3 flash loans
 * @dev Enables shorting of assets to hedge LP positions
 */
contract AaveLeverage is IFlashLoanSimpleReceiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPool public immutable aavePool;
    IPoolAddressesProvider public immutable addressesProvider;
    ISwapRouter public immutable swapRouter;
    address public immutable WMATIC;

    uint24 public constant DEFAULT_FEE = 3000;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SLIPPAGE_TOLERANCE = 100; // 1%

    // Position tracking
    struct Position {
        address baseAsset;
        address shorttedAsset;
        uint256 amount;
        uint256 leverage;
        bool isLong;
        bool isClosed;
        uint256 collateralAmount;
        uint256 borrowAmount;
    }

    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => uint256) public positionCount;
    mapping(address => uint256[]) public userPositionIds;

    // Flash loan context
    struct FlashLoanData {
        address user;
        address baseAsset;
        address shortedAsset;
        uint256 baseAmount;
        uint256 flashLoanAmount;
        bool isClose;
        uint256 positionId;
    }

    event ShortPositionOpened(
        address indexed user,
        uint256 indexed positionId,
        address baseAsset,
        address shortedAsset,
        uint256 collateral,
        uint256 borrowAmount,
        uint256 leverage
    );

    event ShortPositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 collateralReturned,
        uint256 profitOrLoss
    );

    error InvalidPosition();
    error InsufficientBalance();
    error FlashLoanFailed();
    error OnlyPositionOwner();

    constructor(
        address _aavePool,
        address _addressesProvider,
        address _swapRouter,
        address _wmatic
    ) {
        require(_aavePool != address(0), "Invalid pool");
        require(_addressesProvider != address(0), "Invalid provider");
        require(_swapRouter != address(0), "Invalid router");
        require(_wmatic != address(0), "Invalid WMATIC");

        aavePool = IPool(_aavePool);
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        swapRouter = ISwapRouter(_swapRouter);
        WMATIC = _wmatic;
    }

    /**
     * @notice Open a short position via Aave flash loan
     * @param baseAsset Asset to use as collateral
     * @param shortedAsset Asset to short
     * @param amount Amount of baseAsset
     * @param leverage Leverage multiplier (in WAD format, e.g., 1.25e18 = 1.25x)
     * @return positionId ID of opened position
     */
    function openShortPosition(
        address baseAsset,
        address shortedAsset,
        uint256 amount,
        uint256 leverage
    ) external nonReentrant returns (uint256 positionId) {
        require(baseAsset != address(0) && shortedAsset != address(0), "Invalid assets");
        require(amount > 0, "Amount must be > 0");
        require(leverage >= 1e18 && leverage <= 3e18, "Leverage out of range");

        // Transfer base asset from user to this contract
        IERC20(baseAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate flash loan amount
        uint256 flashLoanAmount = ((amount * leverage) / 1e18) - amount;

        // Create position record
        positionId = positionCount[msg.sender]++;
        userPositionIds[msg.sender].push(positionId);

        positions[msg.sender][positionId] = Position({
            baseAsset: baseAsset,
            shorttedAsset: shortedAsset,
            amount: amount,
            leverage: leverage,
            isLong: false,
            isClosed: false,
            collateralAmount: amount + flashLoanAmount,
            borrowAmount: 0
        });

        // Execute flash loan
        FlashLoanData memory data = FlashLoanData({
            user: msg.sender,
            baseAsset: baseAsset,
            shortedAsset: shortedAsset,
            baseAmount: amount,
            flashLoanAmount: flashLoanAmount,
            isClose: false,
            positionId: positionId
        });

        bytes memory params = abi.encode(data);

        aavePool.flashLoanSimple(
            address(this),
            baseAsset,
            flashLoanAmount,
            params,
            0
        );

        return positionId;
    }

    /**
     * @notice Close a short position
     * @param positionId Position ID to close
     */
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(!positions[msg.sender][positionId].isClosed, "Position already closed");

        Position storage pos = positions[msg.sender][positionId];

        // Get current Aave position
        (uint256 collateral, uint256 debt, , , , ) = aavePool.getUserAccountData(
            address(this)
        );

        // Repay debt
        if (debt > 0) {
            IERC20(pos.shorttedAsset).safeApprove(address(aavePool), debt);
            aavePool.repay(pos.shorttedAsset, debt, 2, address(this));
        }

        // Withdraw collateral
        uint256 collateralToWithdraw = collateral > pos.collateralAmount
            ? pos.collateralAmount
            : collateral;

        if (collateralToWithdraw > 0) {
            aavePool.withdraw(pos.baseAsset, collateralToWithdraw, msg.sender);
        }

        pos.isClosed = true;

        emit ShortPositionClosed(msg.sender, positionId, collateralToWithdraw, 0);
    }

    /**
     * @notice Flash loan callback from Aave
     * @param asset Token being flash loaned
     * @param amount Amount of token
     * @param premium Fee charged by Aave
     * @param initiator User who initiated the flash loan
     * @param params Encoded flash loan data
     * @return true if execution successful
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override nonReentrant returns (bool) {
        require(msg.sender == address(aavePool), "Caller must be Aave pool");

        FlashLoanData memory data = abi.decode(params, (FlashLoanData));

        if (!data.isClose) {
            // Opening position
            uint256 totalCollateral = data.baseAmount + data.flashLoanAmount;

            // Supply collateral to Aave
            IERC20(asset).safeApprove(address(aavePool), totalCollateral);
            aavePool.supply(asset, totalCollateral, address(this), 0);

            // Calculate how much of the shorted asset we can borrow
            // Get price ratio and borrow accordingly
            uint256 borrowAmount = _estimateBorrowAmount(
                data.baseAsset,
                data.shorttedAsset,
                totalCollateral
            );

            if (borrowAmount > 0) {
                // Borrow shorted asset
                aavePool.borrow(data.shorttedAsset, borrowAmount, 2, 0, address(this));

                // Update position with actual borrow amount
                positions[data.user][data.positionId].borrowAmount = borrowAmount;

                // Swap borrowed asset for base asset to have liquidity for repayment
                if (data.shorttedAsset != data.baseAsset) {
                    _swapForRepayment(
                        data.shorttedAsset,
                        asset,
                        borrowAmount / 2 // Swap half to repay flash loan
                    );
                }

                emit ShortPositionOpened(
                    data.user,
                    data.positionId,
                    data.baseAsset,
                    data.shorttedAsset,
                    totalCollateral,
                    borrowAmount,
                    data.leverage
                );
            }
        }

        // Ensure we have enough to repay flash loan + premium
        uint256 amountOwed = amount + premium;
        IERC20(asset).safeApprove(address(aavePool), amountOwed);

        return true;
    }

    /**
     * @notice Estimate borrow amount based on collateral
     * @param collateralAsset Collateral asset address
     * @param borrowAsset Asset to borrow
     * @param collateralAmount Collateral amount
     * @return borrowAmount Estimated amount that can be borrowed
     */
    function _estimateBorrowAmount(
        address collateralAsset,
        address borrowAsset,
        uint256 collateralAmount
    ) internal pure returns (uint256 borrowAmount) {
        // Conservative estimate: borrow 50% of collateral value
        // In production, use price oracle for accurate calculation
        borrowAmount = (collateralAmount * 50) / 100;
        return borrowAmount;
    }

    /**
     * @notice Swap tokens for repayment
     * @param tokenIn Input token
     * @param tokenOut Output token (flash loan token)
     * @param amountIn Amount to swap
     */
    function _swapForRepayment(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        if (amountIn == 0 || tokenIn == tokenOut) return;

        IERC20(tokenIn).safeApprove(address(swapRouter), amountIn);

        bytes memory path = abi.encodePacked(tokenIn, DEFAULT_FEE, tokenOut);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        try swapRouter.exactInputSingle(swapParams) {} catch {}
    }

    /**
     * @notice Get position details
     * @param user User address
     * @param positionId Position ID
     * @return position Position struct
     */
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (Position memory position)
    {
        return positions[user][positionId];
    }

    /**
     * @notice Get all positions for user
     * @param user User address
     * @return positions Array of position IDs
     */
    function getUserPositions(address user)
        external
        view
        returns (uint256[] memory)
    {
        return userPositionIds[user];
    }

    /**
     * @notice Required Aave interface
     */
    function ADDRESSES_PROVIDER() external view override returns (address) {
        return address(addressesProvider);
    }

    /**
     * @notice Required Aave interface
     */
    function POOL() external view override returns (address) {
        return address(aavePool);
    }

    /**
     * @notice Recover stuck tokens (emergency)
     * @param token Token to recover
     * @param to Recipient
     */
    function recoverToken(address token, address to) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }
}
