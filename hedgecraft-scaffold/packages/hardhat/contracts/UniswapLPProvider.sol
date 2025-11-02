// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface INonfungiblePositionManager is IERC721Receiver {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function burn(uint256 tokenId) external;
}

/**
 * @title UniswapLPProvider
 * @notice Manages Uniswap V3 liquidity positions for PolygonHedge
 * @dev Handles LP position creation, modification, and fee collection
 */
contract UniswapLPProvider is IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    // Position tracking
    mapping(address => mapping(uint256 => bool)) public userLPPositions;
    mapping(uint256 => address) public positionOwner;
    mapping(address => uint256[]) public userPositionIds;

    // Constants
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;
    uint24 public constant DEFAULT_FEE = 3000; // 0.3%

    event LPPositionCreated(
        address indexed user,
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event LPPositionIncreased(
        address indexed user,
        uint256 indexed tokenId,
        uint128 addedLiquidity,
        uint256 amount0,
        uint256 amount1
    );

    event LPPositionDecreased(
        address indexed user,
        uint256 indexed tokenId,
        uint128 removedLiquidity,
        uint256 amount0,
        uint256 amount1
    );

    event FeesCollected(
        address indexed user,
        uint256 indexed tokenId,
        uint256 fees0,
        uint256 fees1
    );

    error InvalidPoolConfig();
    error OnlyPositionOwner();
    error InvalidPosition();

    constructor(address _nftPositionManager) {
        require(_nftPositionManager != address(0), "Invalid position manager");
        nonfungiblePositionManager = INonfungiblePositionManager(_nftPositionManager);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Create a new liquidity position
     * @param token0 First token in pair
     * @param token1 Second token in pair
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @param tickLower Lower tick bound
     * @param tickUpper Upper tick bound
     * @return tokenId NFT token ID of LP position
     * @return liquidity Liquidity amount
     * @return used0 Actual amount0 used
     * @return used1 Actual amount1 used
     */
    function createLPPosition(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    )
        external
        nonReentrant
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 used0,
            uint256 used1
        )
    {
        require(token0 != address(0) && token1 != address(0), "Invalid tokens");
        require(amount0 > 0 || amount1 > 0, "Insufficient amounts");
        require(tickLower < tickUpper, "Invalid tick range");
        require(tickLower >= MIN_TICK && tickUpper <= MAX_TICK, "Ticks out of range");

        // Ensure token0 < token1
        if (token0 > token1) (token0, token1) = (token1, token0);

        // Transfer tokens from user
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        // Approve position manager
        IERC20(token0).safeApprove(address(nonfungiblePositionManager), amount0);
        IERC20(token1).safeApprove(address(nonfungiblePositionManager), amount1);

        // Mint position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
            .MintParams({
                token0: token0,
                token1: token1,
                fee: DEFAULT_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            });

        (tokenId, liquidity, used0, used1) = nonfungiblePositionManager.mint(params);

        // Track position
        userLPPositions[msg.sender][tokenId] = true;
        positionOwner[tokenId] = msg.sender;
        userPositionIds[msg.sender].push(tokenId);

        // Return unused tokens
        if (amount0 > used0) {
            IERC20(token0).safeTransfer(msg.sender, amount0 - used0);
        }
        if (amount1 > used1) {
            IERC20(token1).safeTransfer(msg.sender, amount1 - used1);
        }

        emit LPPositionCreated(msg.sender, tokenId, liquidity, used0, used1);

        return (tokenId, liquidity, used0, used1);
    }

    /**
     * @notice Increase liquidity in existing position
     * @param tokenId Position NFT token ID
     * @param amount0 Additional amount of token0
     * @param amount1 Additional amount of token1
     * @return liquidity Added liquidity
     * @return used0 Actual amount0 used
     * @return used1 Actual amount1 used
     */
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    )
        external
        nonReentrant
        returns (
            uint128 liquidity,
            uint256 used0,
            uint256 used1
        )
    {
        require(userLPPositions[msg.sender][tokenId], "Not your position");
        require(amount0 > 0 || amount1 > 0, "Insufficient amounts");

        // Get position info
        (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager
            .positions(tokenId);

        // Transfer and approve tokens
        if (amount0 > 0) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
            IERC20(token0).safeApprove(address(nonfungiblePositionManager), amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            IERC20(token1).safeApprove(address(nonfungiblePositionManager), amount1);
        }

        // Increase liquidity
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (liquidity, used0, used1) = nonfungiblePositionManager.increaseLiquidity(params);

        // Return unused tokens
        if (amount0 > used0 && used0 > 0) {
            IERC20(token0).safeTransfer(msg.sender, amount0 - used0);
        }
        if (amount1 > used1 && used1 > 0) {
            IERC20(token1).safeTransfer(msg.sender, amount1 - used1);
        }

        emit LPPositionIncreased(msg.sender, tokenId, liquidity, used0, used1);

        return (liquidity, used0, used1);
    }

    /**
     * @notice Decrease liquidity from position
     * @param tokenId Position NFT token ID
     * @param liquidity Amount of liquidity to remove
     * @return amount0 Amount of token0 withdrawn
     * @return amount1 Amount of token1 withdrawn
     */
    function decreaseLiquidity(uint256 tokenId, uint128 liquidity)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(userLPPositions[msg.sender][tokenId], "Not your position");

        // Decrease liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        // Collect tokens
        INonfungiblePositionManager.CollectParams memory collectParams =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        nonfungiblePositionManager.collect(collectParams);

        emit LPPositionDecreased(msg.sender, tokenId, liquidity, amount0, amount1);

        return (amount0, amount1);
    }

    /**
     * @notice Collect accumulated fees from position
     * @param tokenId Position NFT token ID
     * @return fees0 Fees collected in token0
     * @return fees1 Fees collected in token1
     */
    function collectFees(uint256 tokenId)
        external
        nonReentrant
        returns (uint256 fees0, uint256 fees1)
    {
        require(userLPPositions[msg.sender][tokenId], "Not your position");

        // Get position to check fees
        (, , , , , , , , , , uint128 tokensOwed0, uint128 tokensOwed1) =
            nonfungiblePositionManager.positions(tokenId);

        // Collect
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: tokensOwed0,
                amount1Max: tokensOwed1
            });

        (fees0, fees1) = nonfungiblePositionManager.collect(params);

        emit FeesCollected(msg.sender, tokenId, fees0, fees1);

        return (fees0, fees1);
    }

    /**
     * @notice Get position details
     * @param tokenId Position NFT token ID
     * @return token0 First token
     * @return token1 Second token
     * @return fee Pool fee
     * @return tickLower Lower tick
     * @return tickUpper Upper tick
     * @return liquidity Liquidity amount
     * @return tokensOwed0 Uncollected fees in token0
     * @return tokensOwed1 Uncollected fees in token1
     */
    function getPositionDetails(uint256 tokenId)
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        (, , token0, token1, fee, tickLower, tickUpper, liquidity, , , tokensOwed0, tokensOwed1) =
            nonfungiblePositionManager.positions(tokenId);

        return (token0, token1, fee, tickLower, tickUpper, liquidity, tokensOwed0, tokensOwed1);
    }

    /**
     * @notice Get all positions for user
     * @param user User address
     * @return positions Array of position token IDs
     */
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return userPositionIds[user];
    }
}