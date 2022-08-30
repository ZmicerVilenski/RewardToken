const Fabric = artifacts.require("Fabric");
const RewardToken = artifacts.require("RewardToken");
const AutostakeToken = artifacts.require("AutostakeToken");
const helper = require('./utils/utils.js');

contract("Fabric", (accounts) => {

  const deployer = accounts[0];
  const txFeeAddress = accounts[9];
  let autoStakeTokenAddress, rewardTokenAddress, autoStakeToken, rewardToken;

  const changeTime = async (sec) => {
    const originalBlock = await web3.eth.getBlock('latest');
    await helper.advanceTimeAndBlock(sec); // 
    const newBlock = await web3.eth.getBlock('latest');

    console.log('---------------TIME CHANGING---------------');
    console.log('  before: ', originalBlock.timestamp);
    console.log('  after: ', newBlock.timestamp);
  }

  it("Deploy Fabric and Create Autostake Tokens", async () => {

    console.log('Deployer: ', deployer);

    const fabric = await Fabric.deployed();
    const name = "Auto-stake Token";
    const symbol = "AST";
    // First Auto-stake Token deployment
    let salt = '0x0000000000000000000000000000000000000000000000000000000000000000';
    let tx = await fabric.createAutostakeToken(salt, name, symbol, txFeeAddress, { from: deployer });
    //console.log('Logs: ', tx.logs[0].args);
    // Second Auto-stake Token deployment
    salt = '0x0000000000000000000000000000000000000000000000000000000000000001';
    tx = await fabric.createAutostakeToken(salt, name, symbol, txFeeAddress, { from: deployer });
    //console.log('Logs: ', tx.logs[0].args);

    // events
    let options = {fromBlock: 0, toBlock: 'latest'};
    let events = await fabric.getPastEvents('TokenCreated', options);
    //1
    let event = events[0].returnValues;
    console.log('--- Deploy 1 ---');
    console.log('owner:            ', event.owner);
    console.log('deployedAddress:  ', event.deployedAddress);
    console.log('predictedAddress: ', event.predictedAddress);
    //2
    event = events[1].returnValues;
    console.log('--- Deploy 2 ---');
    console.log('owner:            ', event.owner);
    console.log('deployedAddress:  ', event.deployedAddress);
    console.log('predictedAddress: ', event.predictedAddress);
    //

    autoStakeTokenAddress = event.deployedAddress;

  });

  it("Deploy Reward Token and Verify Autostake Token Owner", async () => {

    rewardToken = await RewardToken.deployed();
    rewardTokenAddress = rewardToken.address;
    autoStakeToken = await AutostakeToken.at(autoStakeTokenAddress);
    // Verify Autostake Token Owner
    const owner = await autoStakeToken.owner.call();
    console.log('Autostake Token Owner: ', owner);
    assert.equal(owner, deployer, "Owner not Deployer");

  });

  it("Set Autostake Token parameters", async () => {

    let tx = await autoStakeToken.setRewardsToken(rewardTokenAddress,  { from: deployer });
    //console.log('Logs: ', tx.logs[0].args);
    const start = Math.round(Date.now() / 1000);
    const end = start + 86400 * 14; // 2 weeks
    const rate = 1000000; // wei per sec
    tx = await autoStakeToken.setRewards(start, end, rate, { from: deployer });
    //console.log('Logs: ', tx.logs[0].args);
    
    // events
    let options = {fromBlock: 0, toBlock: 'latest'};
    let events = await autoStakeToken.getPastEvents('RewardsTokenSet', options);
    let event = events[0].returnValues;
    console.log('Rewards Token address: ', event.token, '. RTA: ', rewardTokenAddress);
    assert.equal(event.token, rewardTokenAddress, "Reward token address not correct");
    //
    events = await autoStakeToken.getPastEvents('RewardsSet', options);
    event = events[0].returnValues;
    console.log('Reward seted. Start: ', event.start, '. End: ', event.end, '. Rate: ', event.rate);

  });

  it("Send Reward tokens to Autostake Token contract", async () => {

    let balanceOfOwner = await rewardToken.balanceOf(deployer);
    console.log('1. Owner balance (Reward Token):', BigInt(balanceOfOwner));
    tx = await rewardToken.transfer(autoStakeTokenAddress, balanceOfOwner, { from: deployer });
    //console.log('Logs: ', tx.logs[0].args);
    balanceOfOwner = await rewardToken.balanceOf(deployer);
    console.log('2. Owner balance (Reward Token):', BigInt(balanceOfOwner));
    balanceOfAutoStake = await rewardToken.balanceOf(autoStakeTokenAddress);
    console.log('Autostake Contract balance (Reward Token):', BigInt(balanceOfAutoStake));

  });

  it("Send Autostake Tokens to the holders", async () => {

    let balanceOfOwner = await autoStakeToken.balanceOf(deployer);
    console.log('Owner balance (Autostake Token):', BigInt(balanceOfOwner));
    let balanceOftxFee = await autoStakeToken.balanceOf(txFeeAddress);
    console.log('TX FEE balance (Autostake Token):', BigInt(balanceOftxFee));
    const amount = web3.utils.toWei('1000', 'ether');
    for (let i = 1; i < 7; i++) { 
      tx = await autoStakeToken.transfer(accounts[i], amount, { from: deployer });
      //console.log('Logs: ', tx.logs[0].args);
    }
    for (let i = 1; i < 7; i++) { 
      balanceOfHolder = await autoStakeToken.balanceOf(accounts[i]);
      console.log('Holder '+i+' balance (Autostake Token):', BigInt(balanceOfHolder));
    }
    balanceOfOwner = await autoStakeToken.balanceOf(deployer);
    console.log('Owner balance (Autostake Token):', BigInt(balanceOfOwner));
    balanceOftxFee = await autoStakeToken.balanceOf(txFeeAddress);
    console.log('TX FEE balance (Autostake Token):', BigInt(balanceOftxFee));

  });  

  it("Claim holders rewards", async () => {

    for (let i = 1; i < 7; i++) { 
      balanceOfHolder = await rewardToken.balanceOf(accounts[i]);
      console.log('Holder '+i+' balance (Reward Token):', BigInt(balanceOfHolder));
    }
    await changeTime(86400);
    const amount = web3.utils.toWei('1', 'ether');
    for (let i = 1; i < 7; i++) { 
      tx = await autoStakeToken.transfer(accounts[i-1], amount, { from: accounts[i] });
      //console.log('Logs: ', tx.logs[0].args);
    }
    await changeTime(86400);
    for (let i = 1; i < 7; i++) { 
      tx = await autoStakeToken.claim(accounts[i]);
      //console.log('Logs: ', tx.logs[0].args);
    }
    for (let i = 1; i < 7; i++) { 
      balanceOfHolder = await rewardToken.balanceOf(accounts[i]);
      console.log('Holder '+i+' balance (Reward Token):', BigInt(balanceOfHolder));
    }

  }); 

});