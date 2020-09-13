pragma solidity ^0.5.16;

import "./openzeppelin/contracts/math/Math.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";

import "./openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./LPTokenWrapper.sol";
import "./Halt.sol";


contract MinePoolDelegate is LPTokenWrapper,Halt {


    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
            userGetRewardTime[account] = now;
        }
        _;
    }

    constructor (address _liquidpool,address _fnxaddress) public {
        require(_liquidpool != address(0));
        require(_fnxaddress != address(0));
        
        lp  = IERC20(_liquidpool);
        fnx = IERC20(_fnxaddress);
    }
    
    function setMineRate(uint256 _reward,uint256 _duration) external onlyOwner updateReward(address(0)) {
        require(_reward>0);
        require(_duration>0);
        
        rewardPerTokenRecord.push(rewardPerToken());
        rateChangeTimeRecord.push(now);
        
        //token number per seconds
        rewardRate = _reward.div(_duration);
        require(rewardRate > 0);
        
        lastUpdateTime = now;        
        reward = _reward;
        duration = _duration;
        
    }   
    
    function setPeriodFinish(uint256 _periodfinish) external onlyOwner {
        require(_periodfinish > now);
        periodFinish = _periodfinish;
    }  
    
    /**
     * @dev getting back the left mine token
     * @param reciever the reciever for getting back mine token
     */
    function getbackLeftMiningToken(address reciever)  public onlyOwner {
        uint256 bal =  fnx.balanceOf(address(this));
        fnx.transfer(reciever,bal);
    }  
        
//////////////////////////public function/////////////////////////////////    

    function lastTimeRewardApplicable() public view returns(uint256) {
         return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns(uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalSupply())
        );
    }

    function earned(address account) public view returns(uint256) {
        return balanceOf(account).mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function stake(uint256 amount) public updateReward(msg.sender) notHalted {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) public updateReward(msg.sender) notHalted {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() public notHalted {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public notHalted {
        uint256 reward = 0;
        if (userGetRewardTime[msg.sender] < lastUpdateTime) {
            reward = getHistoryReward();
        } 
        reward = reward.add(earned(msg.sender));
        
        if (reward > 0) {
            rewards[msg.sender] = 0;
            fnx.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getHistoryReward() internal view returns(uint256) {
         uint256 i;
         uint256 reward;
          for (i=0; i<rateChangeTimeRecord.length; i++) {
             if(i == rateChangeTimeRecord.length - 1) {
                 break;
             }
             
             if (userGetRewardTime[msg.sender] > rateChangeTimeRecord[i]) {
                 if(userGetRewardTime[msg.sender] < rateChangeTimeRecord[i+1] ) {
                    reward = reward.add(balanceOf(msg.sender).mul(rewardPerTokenRecord[i].sub(userRewardPerTokenPaid[msg.sender])).div(1e18)); 
                 } else {
                    reward = reward.add(balanceOf(msg.sender).mul(rewardPerTokenRecord[i]).div(1e18));
                 }
             }  
          }
          
          return reward;
         
      }       

}