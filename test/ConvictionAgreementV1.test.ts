import { expect } from "chai";
import hre, { deployments, waffle, ethers, web3 } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { BigNumberish, Contract, Wallet } from "ethers/lib/ethers";
import { resourceLimits } from "worker_threads";
import { ConstantFlowAgreementV1, ConvictionAgreementV1, ConvictionApp, SuperAppBase, SuperfluidToken, SuperHookableToken, SuperHookManager, TestApp } from "../typechain";
import internal from "stream";
import { assert } from "console";
const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework.js");

const SuperfluidSDK = require("@superfluid-finance/js-sdk");

describe("ConvictionAgreementV1", async () => {
  // const [user1, user2, user3] = await ethers.getSigners();

  const [user1, user2, user3] = waffle.provider.getWallets();
  const abiCoder = new ethers.utils.AbiCoder();

  const setupTokenAndHook = async (sf: any) => {
    const testTokenFactory = await ethers.getContractFactory("TestToken");
    const testToken = await testTokenFactory.deploy("HiToken", "Hi", 18);
    const superTokenFactory = await ethers.getContractFactory("SuperHookableToken");

    const hookManagerFactory = await ethers.getContractFactory("SuperHookManager");

    const hookManager = await hookManagerFactory.deploy();

    const superHookableToken = await superTokenFactory.deploy(sf.host.address);
    await superHookableToken['initialize(address,uint8,string,string,address)'](testToken.address, 18, ":", "Hix", hookManager.address);

    await expect(superHookableToken.connect(user2).upgrade(10)).to.be.revertedWith("ERC20: transfer amount exceeds balance");


    await testToken.mint(user1.address, ethers.utils.parseEther("1"));
    await testToken.mint(user2.address, ethers.utils.parseEther("2"));
    await testToken.mint(user3.address, ethers.utils.parseEther("200"));

    await testToken.connect(user1).increaseAllowance(superHookableToken.address, ethers.utils.parseEther("1"));
    await testToken.connect(user2).increaseAllowance(superHookableToken.address, ethers.utils.parseEther("2"));
    await testToken.connect(user3).increaseAllowance(superHookableToken.address, ethers.utils.parseEther("200"));

    await superHookableToken.connect(user1).upgrade(ethers.utils.parseEther("1"));
    await superHookableToken.connect(user2).upgrade(ethers.utils.parseEther("1"));
    await superHookableToken.connect(user3).upgrade(ethers.utils.parseEther("100"));

    expect(await superHookableToken.balanceOf(user2.address)).to.be.equal(ethers.utils.parseEther("1"));

    return {
      superHookableToken,
      hookManager
    }
  }

  const setupAgreement = async (sf: any, hookManager: SuperHookManager) => {
    /// agreement
    const mathUtilsFactory = await ethers.getContractFactory("mathUtils");
    const mathUtils = await mathUtilsFactory.deploy()

    const agreementFactory = await ethers.getContractFactory("ConvictionAgreementV1", {
      libraries: {
        "mathUtils": mathUtils.address
      }
    });
    const agreement = await agreementFactory.deploy();


    const ISuperfluidGovernance = await sf.contracts['ISuperfluidGovernance'];
    const goveranceAddress = await sf.host.getGovernance();

    const goverance = ISuperfluidGovernance.at(goveranceAddress);
    const atype = await agreement.agreementType();
    await goverance.registerAgreementClass(sf.host.address, agreement.address);

    const agreementProxy = await ethers.getContractAt("ConvictionAgreementV1", await sf.host.getAgreementClass(atype));
    await agreementProxy.setHookManager(hookManager.address);

    const appFactory = await ethers.getContractFactory("TestApp");
    const convictionApp = await appFactory.deploy(sf.host.address, agreementProxy.address);

    return {
      convictionApp,
      agreement,
      agreementProxy
    }

  }


  const setupTests = deployments.createFixture(async ({ deployments }) => {
    await deployments.fixture();

    await deployFramework(createErrorHandler(), {
      newTestResolver: true,
      isTruffle: false,
      web3: web3,

      useMocks: false,
    });

    const sf = new SuperfluidSDK.Framework({
      ethers: waffle.provider,
      version: process.env.RELEASE_VERSION || "test",
      additionalContracts: ['ISuperfluidGovernance']
    });
    await sf.initialize();

    const tokenRelated = await setupTokenAndHook(sf);
    const appAndAgreement = await setupAgreement(sf, tokenRelated.hookManager);

    await tokenRelated.hookManager.registerAgreemenStateHook(appAndAgreement.agreementProxy.address,
      sf.cfa._cfa.address);

    await tokenRelated.hookManager.registerBalanceHook(appAndAgreement.agreementProxy.address);
    const D = 10 ** 7;
    const proposalParam = {
      alpha: 0.9 * D,
      requiredConviction: 1000 * D,
      numSecondPerStep: 60,
      tokenScalingFactor: ethers.utils.parseEther("1")

    }

    return {
      "sf": sf,
      ...tokenRelated,
      ...appAndAgreement,
      proposalParam,
      D
    };
  });

  it("can setup ", async () => {
    await setupTests();
  });


  describe("createProposal()", async () => {
    it("can create proposal ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address, proposalParam, ethers.utils.toUtf8Bytes("hello"), "0x"]
        ),
        "0x");

      await expect(await agreementProxy.getProposalLastConviction(
        superHookableToken.address,
        convictionApp.address,
        0))
        .to.equal(0);

      let proposalData = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);

      expect(proposalData.proposalId).to.equal(0);
      expect(proposalData.app).to.equal(convictionApp.address);
      expect(proposalData.flowRate).to.equal(0);
      expect(proposalData.status).to.equal(0);
      expect(proposalData.lastConviction).to.equal(0);
      expect(proposalData.governToken).to.equal(superHookableToken.address);
      expect(proposalData.param.alpha).to.equal(proposalParam.alpha);
      expect(proposalData.param.requiredConviction).to.equal(proposalParam.requiredConviction);
      expect(proposalData.param.numSecondPerStep).to.equal(proposalParam.numSecondPerStep);
      expect(proposalData.param.tokenScalingFactor).to.equal(proposalParam.tokenScalingFactor);
      expect(ethers.utils.toUtf8String(proposalData.data)).to.equal("hello");

    });
  });

  describe("vote()", async () => {
    it("can vote", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address, proposalParam, ethers.utils.toUtf8Bytes("hello"), "0x"]
        ),
        "0x");



      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x");

      expect(await agreementProxy.getUserVotePercentage(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(1 * D);

      expect(await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(1 * D);

      expect(await agreementProxy.getUserVoteFlow(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(0);

      const proposalIds = await agreementProxy.getVotingProposalsByAppUser(superHookableToken.address,
        convictionApp.address,
        user2.address);

      expect(proposalIds.length).to.equal(1);
      expect(proposalIds[0]).to.equal(0);


      const appProposalIds = await agreementProxy.getVotingProposalsByUser(superHookableToken.address,
        user2.address);

      expect(appProposalIds.length).to.equal(1);
      expect(appProposalIds[0].app).to.equal(convictionApp.address);
      expect(appProposalIds[0].proposalId).to.equal(0);
    });

    it("mutliple people can vote with static amount and calculate conviction correctly", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address, proposalParam, ethers.utils.toUtf8Bytes("hello"), "0x"]
        ),
        "0x");


      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x");

      await sf.host.connect(user3).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 0.5 * D, "0x"]
        ), "0x");


      await ethers.provider.send('evm_increaseTime', [600]);
      await ethers.provider.send('evm_mine', []);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );


      const proposal = await agreementProxy.getProposal(superHookableToken.address,
        convictionApp.address,
        0
      );

      expect(proposal.amount).to.equal(51 * D);

      const res = calConviction(10, 0, 1, 0, 0.9) + calConviction(10, 0, 50, 0, 0.9);

      const resInt = ethers.BigNumber.from(Math.floor(res * 10 ** 3));
      expect(proposal.lastConviction.div(10 ** (7 - 3)).toString()).to.equal(resInt.toString());

    });

    it("mutliple people can vote with flow and calculate conviction correctly", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address, proposalParam, ethers.utils.toUtf8Bytes("hello"), "0x"]
        ),
        "0x");

      await createFlow(sf, superHookableToken, user3, user1, ethers.BigNumber.from(10).pow(14));
      await createFlow(sf, superHookableToken, user3, user2, ethers.BigNumber.from(10).pow(14));


      await sf.host.connect(user1).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 0.5 * D, "0x"]
        ), "0x");

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x");



      await ethers.provider.send('evm_increaseTime', [600]);
      await ethers.provider.send('evm_mine', []);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );


      const proposal = await agreementProxy.getProposal(superHookableToken.address,
        convictionApp.address,
        0
      );


      const newAmount1 = await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0, user1.address);

      const newAmount2 = await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0, user2.address);

      const flowPerStep = (10 ** -4 * proposalParam.numSecondPerStep);

      const res = calConviction(10, 0, newAmount1.toNumber() / D, flowPerStep * 0.5, 0.9)
        + calConviction(10, 0, newAmount2.toNumber() / D, flowPerStep, 0.9);


      const resInt = ethers.BigNumber.from(Math.floor(res * 10 ** 3));
      expect(proposal.lastConviction.div(10 ** (7 - 3)).toString()).to.equal(resInt.toString());


    });


    it("can set proposal to Pass if conviction > threshold", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      const newParam = { ...proposalParam, requiredConviction: 6 * D }
      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        newParam, D, user2);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );

      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );


      let proposal = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);
      expect(proposal.status).to.equal(1);

    });

    it("cannot vote Passed proposal", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      const newParam = { ...proposalParam, requiredConviction: 6 * D }
      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        newParam, D, user2);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );

      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );


      let proposal = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);
      expect(proposal.status).to.equal(1);

      await expect(sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x")).to.be.revertedWith("Can only vote Active Proposal");


    });

    it("can remove User's inactive proposals when user vote", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      const newParam = { ...proposalParam, requiredConviction: 6 * D }
      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        newParam, D, user2);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 0.5 * D, "0x"]
        ), "0x"
      );

      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );


      const userProposals = await agreementProxy.getVotingProposalsByAppUser(superHookableToken.address,
        convictionApp.address, user2.address);
      expect(userProposals.length).to.equal(0);

      const appProposalIds = await agreementProxy.getVotingProposalsByUser(superHookableToken.address,
        user2.address);

      expect(appProposalIds.length).to.equal(0);

    });

    it("can remove User's target active proposals when target percentage = 0", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 0 * D, "0x"]
        ), "0x"
      );

      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );


      const userProposals = await agreementProxy.getVotingProposalsByAppUser(superHookableToken.address,
        convictionApp.address, user2.address);
      expect(userProposals.length).to.equal(0);

      const appProposalIds = await agreementProxy.getVotingProposalsByUser(superHookableToken.address,
        user2.address);

      expect(appProposalIds.length).to.equal(0);

    });

    it("cannot vote with total percentage > 100%", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user3);


      await expect(sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 1, 0.5 * D, "0x"]
        ), "0x"
      )).to.be.revertedWith("Total Voting Percentage must <= 100%");


    });

    it("can vote if another proposal becomes inactive such that total percentage <= 100%", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user3);

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        { ...proposalParam, requiredConviction: 6 * D }, D, user2);


      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x"
      );


    });

  })


  describe("updateProposalConvictionAndStatus()", async () => {
    it("can update Conviction with static Amount", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

    });

    it("can update Conviction with dynamic Amount (Flow)", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address, proposalParam, "0x", "0x"]
        ),
        "0x");


      await createFlow(sf, superHookableToken, user3, user2, ethers.BigNumber.from(10).pow(14));


      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
        ), "0x");

      expect(await agreementProxy.getUserVoteFlow(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.closeTo(ethers.BigNumber.from(10).pow(3).mul(proposalParam.numSecondPerStep), 1);

      await ethers.provider.send('evm_increaseTime', [600]);
      await ethers.provider.send('evm_mine', []);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );

      const newAmount = await agreementProxy.getUserVoteAmount(superHookableToken.address, convictionApp.address,
        0, user2.address);
      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, newAmount.toNumber() / D, (10 ** -4 * proposalParam.numSecondPerStep), 0.9
      );

    });

    it("can set Proposal Pass when local Max > threshold even currentConviction < threshold (Assume still solvent, i.e. currentConviction >= 0)", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "createProposal",
          [superHookableToken.address, convictionApp.address,
          { ...proposalParam, requiredConviction: 5 * D }, "0x", "0x"]
        ),
        "0x");


      await createFlow(sf, superHookableToken, user3, user2, ethers.utils.parseEther("0.001"));


      await sf.host.connect(user3).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "vote",
          [superHookableToken.address, convictionApp.address, 0, 0.01 * D, "0x"]
        ), "0x");


      await ethers.provider.send('evm_increaseTime', [1000 * 60]);
      await ethers.provider.send('evm_mine', []);

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );


      let proposal = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);
      expect(proposal.status).to.equal(1);

    });


  })

  describe("Hook Related Functions", async () => {
    it("can correctly Update Conviction when flow change ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);


      await createFlow(sf, superHookableToken, user3, user2, ethers.BigNumber.from(10).pow(14));


      expect(await agreementProxy.getUserVoteFlow(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.closeTo(ethers.BigNumber.from(10).pow(3).mul(proposalParam.numSecondPerStep), 1);


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

    });


    it("can correctly Update Conviction when downgrade ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);


      await superHookableToken.connect(user2).downgrade(ethers.utils.parseEther("0.5"));

      expect(await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(0.5 * D);


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

    });


    it("can correctly Update Conviction when upgrade ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);


      await superHookableToken.connect(user2).upgrade(ethers.utils.parseEther("1"));

      expect(await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(2 * D);


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

    });



    it("can correctly Update Conviction when transfer ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        proposalParam, D, user2);


      await superHookableToken.connect(user2).transfer(user1.address, ethers.utils.parseEther("0.5"));

      expect(await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(0.5 * D);


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

    });


    it("doesnt Update status && Only Update Conviction on Hook Callback ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam, hookManager } = await setupTests();

      console.log("DEPLOLYED _hookManager");
      console.log(hookManager.address);

      const newParam = { ...proposalParam, requiredConviction: 6 * D }
      await createProposalAndVoteAndWait(sf, agreementProxy, superHookableToken, convictionApp,
        newParam, D, user2);


      await superHookableToken.connect(user2).transfer(user1.address, ethers.utils.parseEther("0.5"));


      let proposal = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);
      expect(proposal.status).to.equal(0);

      expect(await agreementProxy.getUserVoteAmount(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(0.5 * D);


      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );

      await sf.host.connect(user2).callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData(
          "updateProposalConvictionAndStatus",
          [superHookableToken.address, convictionApp.address, 0, "0x"]
        ), "0x"
      );


      proposal = await agreementProxy.getProposal(superHookableToken.address, convictionApp.address, 0);
      expect(proposal.status).to.equal(1);

      await assertConvictionCorrect(agreementProxy, superHookableToken, convictionApp,
        0, 10, 0, 1, 0, 0.9
      );


    });


  })



})

const createErrorHandler = () => {
  return (err: any) => {
    if (err) throw err;
  }

};


const calConviction = (n: number, y_0: number, x_0: number, flowRate: number, alpha: number) => {
  let result = y_0;

  for (let i = 1; i < n + 1; i++) {
    result = result * alpha + x_0 + i * flowRate;
  }
  return result;

}


const assertConvictionCorrect = async (
  agreementProxy: ConvictionAgreementV1,
  superHookableToken: SuperHookableToken,
  convictionApp: TestApp,
  proposalId: number,
  n: number, y_0: number, x_0: number, flowRate: number, alpha: number,
  correctNumDecimal = 3) => {

  const conviction = await agreementProxy.getProposalLastConviction(superHookableToken.address,
    convictionApp.address,
    proposalId
  );

  // console.log("online Conviction", conviction.toString());

  // console.log(n)
  // console.log(y_0)
  // console.log(x_0)
  // console.log(flowRate)
  // console.log(alpha)
  const res = calConviction(n, y_0, x_0, flowRate, alpha);

  const resInt = ethers.BigNumber.from(Math.floor(res * 10 ** correctNumDecimal));
  expect(conviction.div(10 ** (7 - correctNumDecimal)).toString()).to.equal(resInt.toString());

}


const createFlow = async (sf: any,
  superHookableToken: SuperHookableToken,
  from: Wallet, to: Wallet, flowRate: BigNumberish) => {

  const IConstantFlowAgreementV1 = await sf.contracts['IConstantFlowAgreementV1'];
  const cfa = new Contract(sf.cfa._cfa.address, IConstantFlowAgreementV1.abi, ethers.provider);
  console.log(superHookableToken.address);

  await sf.host.connect(from).callAgreement(cfa.address,
    cfa.interface.encodeFunctionData(
      "createFlow",
      [superHookableToken.address, to.address, flowRate, "0x"]
    ), "0x");

}


const createProposalAndVoteAndWait = async (sf: any,
  agreementProxy: ConvictionAgreementV1,
  superHookableToken: SuperHookableToken,
  convictionApp: TestApp,
  proposalParam: any,
  D: number,
  user: Wallet) => {

  await sf.host.callAgreement(agreementProxy.address,
    agreementProxy.interface.encodeFunctionData(
      "createProposal",
      [superHookableToken.address, convictionApp.address, proposalParam, ethers.utils.toUtf8Bytes("hello"), "0x"]
    ),
    "0x");

  await sf.host.connect(user).callAgreement(agreementProxy.address,
    agreementProxy.interface.encodeFunctionData(
      "vote",
      [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
    ), "0x");


  await ethers.provider.send('evm_increaseTime', [600]);
  await ethers.provider.send('evm_mine', []);
}