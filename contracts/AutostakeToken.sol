// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AutostakeToken is ERC20, Ownable {
    event RewardsTokenSet(ERC20 token);
    event RewardsSet(uint32 start, uint32 end, uint256 rate);
    event RewardsPerTokenUpdated(uint256 accumulated);
    event UserRewardsUpdated(
        address user,
        uint256 userRewards,
        uint256 paidRewardPerToken
    );
    event Claimed(address receiver, uint256 claimed);

    uint256 private constant TXFEES = 1; // 1% transaction fee
    uint256 private _totalSupply;
    address private txFeeAddress;
    mapping(address => uint256) private _balanceOf;

    struct RewardsPeriod {
        uint32 start;
        uint32 end;
    }

    struct RewardsPerToken {
        uint128 accumulated;
        uint32 lastUpdated;
        uint96 rate;
    }

    struct UserRewards {
        uint128 accumulated;
        uint128 checkpoint;
    }

    ERC20 public rewardsToken;
    RewardsPeriod public rewardsPeriod;

    RewardsPerToken public rewardsPerToken;
    mapping(address => UserRewards) public rewards;

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        address _txFeeAddress
    ) ERC20(name, symbol) {
        txFeeAddress = _txFeeAddress;
        _mint(owner, 1500000000 * 10**18);
    }

    /**
     * @notice Safely cast an uint256 to an u32
     * @param x convertible number
     */
    function u32(uint256 x) internal pure returns (uint32 y) {
        require(x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }

    /**
     * @notice Safely cast an uint256 to an uint128
     * @param x convertible number
     */
    function u128(uint256 x) internal pure returns (uint128 y) {
        require(x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }

    /**
     * @notice Return the earliest of two timestamps
     * @param x timestamp 1
     * @param y timestamp 1
     */
    function earliest(uint32 x, uint32 y) internal pure returns (uint32 z) {
        z = (x < y) ? x : y;
    }

    /**
     * @notice Set a rewards token. Careful, this can only be done once.
     * @param rewardsToken_ reward token
     */
    function setRewardsToken(ERC20 rewardsToken_) external onlyOwner {
        require(rewardsToken == ERC20(address(0)), "Rewards token already set");
        rewardsToken = rewardsToken_;
        emit RewardsTokenSet(rewardsToken_);
    }

    /**
     * @notice Set a rewards schedule
     * @param start timestamp of starting date of reward program
     * @param end timestamp of ending date of reward program
     * @param rate reward in wei per second
     */
    function setRewards(
        uint32 start,
        uint32 end,
        uint96 rate
    ) external onlyOwner {
        require(start <= end, "Incorrect input");
        require(rewardsToken != IERC20(address(0)), "Rewards token not set");
        require(
            u32(block.timestamp) < rewardsPeriod.start ||
                u32(block.timestamp) > rewardsPeriod.end,
            "Ongoing rewards"
        );
        rewardsPeriod.start = start;
        rewardsPeriod.end = end;
        rewardsPerToken.lastUpdated = start;
        rewardsPerToken.rate = rate;

        emit RewardsSet(start, end, rate);
    }

    /**
     * @notice Update the rewards per token accumulator. Needs to be called on each liquidity event
     */
    function _updateRewardsPerToken() internal {
        RewardsPerToken memory rewardsPerToken_ = rewardsPerToken;
        RewardsPeriod memory rewardsPeriod_ = rewardsPeriod;
        uint256 totalSupply_ = _totalSupply;
        if (u32(block.timestamp) < rewardsPeriod_.start) return;
        uint32 end = earliest(u32(block.timestamp), rewardsPeriod_.end);
        uint256 unaccountedTime = end - rewardsPerToken_.lastUpdated;
        if (unaccountedTime == 0) return;
        if (totalSupply_ != 0)
            rewardsPerToken_.accumulated = u128(
                (rewardsPerToken_.accumulated +
                    (1e18 * unaccountedTime * rewardsPerToken_.rate) /
                    totalSupply_)
            );
        rewardsPerToken_.lastUpdated = end;
        rewardsPerToken = rewardsPerToken_;

        emit RewardsPerTokenUpdated(rewardsPerToken_.accumulated);
    }

    /**
     * @notice Accumulate rewards for an user. Needs to be called on each liquidity event, or when user balances change.
     * @param user address of holder
     */
    function _updateUserRewards(address user) internal returns (uint128) {
        UserRewards memory userRewards_ = rewards[user];
        RewardsPerToken memory rewardsPerToken_ = rewardsPerToken;
        userRewards_.accumulated = u128(
            (userRewards_.accumulated +
                (_balanceOf[user] *
                    (rewardsPerToken_.accumulated - userRewards_.checkpoint)) /
                1e18)
        );
        userRewards_.checkpoint = rewardsPerToken_.accumulated;
        rewards[user] = userRewards_;
        emit UserRewardsUpdated(
            user,
            userRewards_.accumulated,
            userRewards_.checkpoint
        );

        return userRewards_.accumulated;
    }

    /**
     * @notice ransfer tokens, after updating rewards for source and destination.
     */
    function _transfer(
        address src,
        address dst,
        uint256 amount
    ) internal virtual override {
        _updateRewardsPerToken();
        _updateUserRewards(src);
        _updateUserRewards(dst);
        uint256 fees = (amount * TXFEES) / 100;
        if (fees > 0) {
            super._transfer(src, txFeeAddress, fees);
            amount -= fees;
        }
        super._transfer(src, dst, amount);
    }

    /**
     * @notice Claim all rewards from caller into a given address
     * @param to address of holder
     */
    function claim(address to) external returns (uint256 claiming) {
        _updateRewardsPerToken();
        claiming = _updateUserRewards(msg.sender);
        rewards[msg.sender].accumulated = 0;
        rewardsToken.transfer(to, claiming);
        emit Claimed(to, claiming);
    }
}
