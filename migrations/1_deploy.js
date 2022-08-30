const Fabric = artifacts.require("Fabric");
const RewardToken = artifacts.require("RewardToken");

module.exports = async function (deployer, network, addresses) {

  console.log("Deploying contracts with the account:", deployer.address);

  await deployer.deploy(RewardToken, "Reward Token", "RWT");
  const rewardToken = await RewardToken.deployed();
  console.log("Reward Token address:", rewardToken.address);

  await deployer.deploy(Fabric);
  const fabric = await Fabric.deployed();
  console.log("Fabric address:", fabric.address);

};
