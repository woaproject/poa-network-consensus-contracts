const BlockReward = artifacts.require('./mockContracts/BlockRewardMock');
const EmissionFunds = artifacts.require('./EmissionFunds');
const EternalStorageProxy = artifacts.require('./mockContracts/EternalStorageProxyMock');
const KeysManager = artifacts.require('./mockContracts/KeysManagerMock');
const PoaNetworkConsensus = artifacts.require('./mockContracts/PoaNetworkConsensusMock');
const ProxyStorage = artifacts.require('./mockContracts/ProxyStorageMock');

const ERROR_MSG = 'VM Exception while processing transaction: revert';

require('chai')
  .use(require('chai-as-promised'))
  .use(require('chai-bignumber')(web3.BigNumber))
  .should();

contract('BlockReward [all features]', function (accounts) {
  let poaNetworkConsensus, proxyStorage, keysManager, emissionFunds, blockReward;
  let blockRewardAmount, emissionFundsAmount;
  const coinbase = accounts[0];
  const masterOfCeremony = accounts[0];
  const miningKey = accounts[1];
  const miningKey2 = accounts[2];
  const miningKey3 = accounts[3];
  const payoutKey = accounts[4];
  const payoutKey2 = accounts[5];
  const payoutKey3 = accounts[6];
  const systemAddress = accounts[7];
  const votingToChangeKeys = accounts[9];
  
  beforeEach(async () => {
    poaNetworkConsensus = await PoaNetworkConsensus.new(masterOfCeremony, []);

    proxyStorage = await ProxyStorage.new();
    const proxyStorageEternalStorage = await EternalStorageProxy.new(0, proxyStorage.address);
    proxyStorage = await ProxyStorage.at(proxyStorageEternalStorage.address);
    await proxyStorage.init(poaNetworkConsensus.address).should.be.fulfilled;

    await poaNetworkConsensus.setProxyStorage(proxyStorage.address);

    keysManager = await KeysManager.new();
    const keysManagerEternalStorage = await EternalStorageProxy.new(proxyStorage.address, keysManager.address);
    keysManager = await KeysManager.at(keysManagerEternalStorage.address);
    await keysManager.init(
      masterOfCeremony,
      "0x0000000000000000000000000000000000000000"
    ).should.be.fulfilled;

    await proxyStorage.initializeAddresses(
      keysManagerEternalStorage.address,
      votingToChangeKeys,
      accounts[9],
      accounts[9],
      accounts[9],
      accounts[9]
    );

    await keysManager.addMiningKey(miningKey, {from: votingToChangeKeys}).should.be.fulfilled;
    await keysManager.addMiningKey(miningKey2, {from: votingToChangeKeys}).should.be.fulfilled;
    await keysManager.addMiningKey(miningKey3, {from: votingToChangeKeys}).should.be.fulfilled;
    await keysManager.addPayoutKey(payoutKey, miningKey, {from: votingToChangeKeys}).should.be.fulfilled;
    await keysManager.addPayoutKey(payoutKey2, miningKey2, {from: votingToChangeKeys}).should.be.fulfilled;
    await keysManager.addPayoutKey(payoutKey3, miningKey3, {from: votingToChangeKeys}).should.be.fulfilled;
    await poaNetworkConsensus.setSystemAddress(coinbase);
    await poaNetworkConsensus.finalizeChange().should.be.fulfilled;
    await poaNetworkConsensus.setSystemAddress('0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE');

    emissionFunds = await EmissionFunds.new(accounts[8]);
    blockRewardAmount = web3.toWei(2, 'ether');
    emissionFundsAmount = web3.toWei(1, 'ether');

    await BlockReward.new(
      0,
      emissionFunds.address,
      blockRewardAmount,
      emissionFundsAmount
    ).should.be.rejectedWith(ERROR_MSG);

    await BlockReward.new(
      proxyStorage.address,
      emissionFunds.address,
      0,
      emissionFundsAmount
    ).should.be.rejectedWith(ERROR_MSG);

    blockReward = await BlockReward.new(
      proxyStorage.address,
      emissionFunds.address,
      blockRewardAmount,
      emissionFundsAmount
    ).should.be.fulfilled;
  });

  describe('constructor', async () => {
    it('should save parameters', async () => {
      proxyStorage.address.should.be.equal(
        await blockReward.proxyStorage()
      );
      emissionFunds.address.should.be.equal(
        await blockReward.emissionFunds()
      );
      blockRewardAmount.should.be.bignumber.equal(
        await blockReward.blockRewardAmount()
      );
      emissionFundsAmount.should.be.bignumber.equal(
        await blockReward.emissionFundsAmount()
      );
    });
  });

  describe('#reward', async () => {
    it('may be called only by system address', async () => {
      await blockReward.reward([miningKey], [0]).should.be.rejectedWith(ERROR_MSG);
      await blockReward.setSystemAddress(systemAddress);
      await blockReward.reward([miningKey], [0], {from: systemAddress}).should.be.fulfilled;
    });

    it('should revert if input array contains more than one item', async () => {
      await blockReward.setSystemAddress(systemAddress);
      await blockReward.reward(
        [miningKey, miningKey2],
        [0, 0],
        {from: systemAddress}
      ).should.be.rejectedWith(ERROR_MSG);
    });

    it('should revert if lengths of input arrays are not equal', async () => {
      await blockReward.setSystemAddress(systemAddress);
      await blockReward.reward(
        [miningKey],
        [0, 0],
        {from: systemAddress}
      ).should.be.rejectedWith(ERROR_MSG);
    });

    it('should revert if `kind` parameter is not 0', async () => {
      await blockReward.setSystemAddress(systemAddress);
      await blockReward.reward(
        [miningKey],
        [1],
        {from: systemAddress}
      ).should.be.rejectedWith(ERROR_MSG);
    });

    it('should revert if mining key does not exist', async () => {
      await keysManager.removeMiningKey(miningKey3, {from: votingToChangeKeys}).should.be.fulfilled;
      await blockReward.setSystemAddress(systemAddress);
      await blockReward.reward(
        [miningKey3],
        [0],
        {from: systemAddress}
      ).should.be.rejectedWith(ERROR_MSG);
      await blockReward.reward(
        [miningKey2],
        [0],
        {from: systemAddress}
      ).should.be.fulfilled;
    });

    it('should assign rewards to payout key and EmissionFunds', async () => {
      await blockReward.setSystemAddress(systemAddress);
      const {logs} = await blockReward.reward(
        [miningKey],
        [0],
        {from: systemAddress}
      ).should.be.fulfilled;
      logs[0].event.should.be.equal('Rewarded');
      logs[0].args.receivers.should.be.deep.equal([payoutKey, emissionFunds.address]);
      logs[0].args.rewards[0].toString().should.be.equal(blockRewardAmount.toString());
      logs[0].args.rewards[1].toString().should.be.equal(emissionFundsAmount.toString());
    });

    it('should assign reward to mining key if payout key is 0', async () => {
      await keysManager.removePayoutKey(
        miningKey,
        {from: votingToChangeKeys}
      ).should.be.fulfilled;

      await blockReward.setSystemAddress(systemAddress);
      const {logs} = await blockReward.reward(
        [miningKey],
        [0],
        {from: systemAddress}
      ).should.be.fulfilled;

      logs[0].event.should.be.equal('Rewarded');
      logs[0].args.receivers.should.be.deep.equal([miningKey, emissionFunds.address]);
      logs[0].args.rewards[0].toString().should.be.equal(blockRewardAmount.toString());
      logs[0].args.rewards[1].toString().should.be.equal(emissionFundsAmount.toString());
    });

    it('should assign reward only to payout key if emissionFundsAmount is 0', async () => {
      blockReward = await BlockReward.new(
        proxyStorage.address,
        emissionFunds.address,
        blockRewardAmount,
        0
      ).should.be.fulfilled;

      await blockReward.setSystemAddress(systemAddress);
      const {logs} = await blockReward.reward(
        [miningKey],
        [0],
        {from: systemAddress}
      ).should.be.fulfilled;
      logs[0].event.should.be.equal('Rewarded');
      logs[0].args.receivers.length.should.be.equal(1);
      logs[0].args.receivers.should.be.deep.equal([payoutKey]);
      logs[0].args.rewards.length.should.be.equal(1);
      logs[0].args.rewards[0].toString().should.be.equal(blockRewardAmount.toString());
    });
  });
});