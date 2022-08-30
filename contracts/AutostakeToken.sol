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

    uint256 private constant TXFEES = 1; // 1%
    uint256 private _totalSupply;
    address private txFeeAddress;
    mapping(address => uint256) private _balanceOf;

    struct RewardsPeriod {
        uint32 start; // Start time for the current rewardsToken schedule
        uint32 end; // End time for the current rewardsToken schedule
    }

    struct RewardsPerToken {
        uint128 accumulated; // Accumulated rewards per token for the period, scaled up by 1e18
        uint32 lastUpdated; // Last time the rewards per token accumulator was updated
        uint96 rate; // Wei rewarded per second among all token holders
    }

    struct UserRewards {
        uint128 accumulated; // Accumulated rewards for the user until the checkpoint
        uint128 checkpoint; // RewardsPerToken the last time the user rewards were updated
    }

    ERC20 public rewardsToken; // Token used as rewards
    RewardsPeriod public rewardsPeriod; // Period in which rewards are accumulated by users

    RewardsPerToken public rewardsPerToken; // Accumulator to track rewards per token
    mapping(address => UserRewards) public rewards; // Rewards accumulated by users

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        address _txFeeAddress
    ) ERC20(name, symbol) {
        txFeeAddress = _txFeeAddress;
        _mint(owner, 1500000000 * 10**18);
    }

    /// @dev Safely cast an uint256 to an u32
    function u32(uint256 x) internal pure returns (uint32 y) {
        require(x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }

    /// @dev Safely cast an uint256 to an uint128
    function u128(uint256 x) internal pure returns (uint128 y) {
        require(x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }

    /// @dev Return the earliest of two timestamps
    function earliest(uint32 x, uint32 y) internal pure returns (uint32 z) {
        z = (x < y) ? x : y;
    }

    /// @dev Set a rewards token.
    /// @notice Careful, this can only be done once.
    function setRewardsToken(ERC20 rewardsToken_) external onlyOwner {
        require(rewardsToken == ERC20(address(0)), "Rewards token already set");
        rewardsToken = rewardsToken_;
        emit RewardsTokenSet(rewardsToken_);
    }

    /// @dev Set a rewards schedule
    function setRewards(
        uint32 start,
        uint32 end,
        uint96 rate
    ) external onlyOwner {
        require(start <= end, "Incorrect input");
        require(rewardsToken != IERC20(address(0)), "Rewards token not set");
        // A new rewards program can be set if one is not running
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

    /// @dev Update the rewards per token accumulator.
    /// @notice Needs to be called on each liquidity event
    function _updateRewardsPerToken() internal {
        RewardsPerToken memory rewardsPerToken_ = rewardsPerToken;
        RewardsPeriod memory rewardsPeriod_ = rewardsPeriod;
        uint256 totalSupply_ = _totalSupply;
        if (u32(block.timestamp) < rewardsPeriod_.start) return;
        uint32 end = earliest(u32(block.timestamp), rewardsPeriod_.end);
        uint256 unaccountedTime = end - rewardsPerToken_.lastUpdated; // Cast to uint256 to avoid overflows later on
        if (unaccountedTime == 0) return; // We skip the storage changes if already updated in the same block
        // Calculate and update the new value of the accumulator. unaccountedTime casts it into uint256, which is desired.
        // If the first mint happens mid-program, we don't update the accumulator, no one gets the rewards for that period.
        if (totalSupply_ != 0)
            rewardsPerToken_.accumulated = u128(
                (rewardsPerToken_.accumulated +
                    (1e18 * unaccountedTime * rewardsPerToken_.rate) /
                    totalSupply_)
            ); // The rewards per token are scaled up for precision
        rewardsPerToken_.lastUpdated = end;
        rewardsPerToken = rewardsPerToken_;

        emit RewardsPerTokenUpdated(rewardsPerToken_.accumulated);
    }

    /// @dev Accumulate rewards for an user.
    /// @notice Needs to be called on each liquidity event, or when user balances change.
    function _updateUserRewards(address user) internal returns (uint128) {
        UserRewards memory userRewards_ = rewards[user];
        RewardsPerToken memory rewardsPerToken_ = rewardsPerToken;
        userRewards_.accumulated = u128(
            (userRewards_.accumulated +
                (_balanceOf[user] *
                    (rewardsPerToken_.accumulated - userRewards_.checkpoint)) /
                1e18)
        ); // Must scale down the rewards by the precision factor
        userRewards_.checkpoint = rewardsPerToken_.accumulated;
        rewards[user] = userRewards_;
        emit UserRewardsUpdated(
            user,
            userRewards_.accumulated,
            userRewards_.checkpoint
        );

        return userRewards_.accumulated;
    }

    /// @dev Transfer tokens, after updating rewards for source and destination.
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

    /// @dev Claim all rewards from caller into a given address
    function claim(address to) external returns (uint256 claiming) {
        _updateRewardsPerToken();
        claiming = _updateUserRewards(msg.sender);
        rewards[msg.sender].accumulated = 0; // A Claimed event implies the rewards were set to zero
        rewardsToken.transfer(to, claiming);
        emit Claimed(to, claiming);
    }
}
