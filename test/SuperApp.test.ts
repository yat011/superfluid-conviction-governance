import { expect } from "chai";
import hre, { deployments, waffle, ethers, web3 } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { BigNumberish, Contract } from "ethers/lib/ethers";
const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework.js");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");

const SuperfluidSDK = require("@superfluid-finance/js-sdk");

describe("SuperHookableToken", async () => {
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

    await testToken.mint(user2.address, 10);

    await testToken.mint(user3.address, ethers.utils.parseEther("200"));

    await testToken.connect(user2).increaseAllowance(superHookableToken.address, 10);
    await testToken.connect(user3).increaseAllowance(superHookableToken.address, ethers.utils.parseEther("200"));

    await superHookableToken.connect(user2).upgrade(10);
    await superHookableToken.connect(user3).upgrade(ethers.utils.parseEther("100"));

    expect(await superHookableToken.balanceOf(user2.address)).to.be.equal(10);

    return {
      superHookableToken,
      hookManager
    }
  }

  const setupAgreement = async (sf: any) => {
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
    const appFactory = await ethers.getContractFactory("ConvictionApp");
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
    const appAndAgreement = await setupAgreement(sf);

    await tokenRelated.hookManager.registerAgreemenStateHook(appAndAgreement.agreementProxy.address,
      sf.cfa._cfa.address);

    await tokenRelated.hookManager.registerBalanceHook(appAndAgreement.agreementProxy.address);


    return {
      "sf": sf,
      ...tokenRelated,
      ...appAndAgreement
    };
  });

  it("can setup ", async () => {
    await setupTests();
  });


  describe("Agreement", async () => {

    // it("can be voted ", async () => {
    //   const { sf, superHookableToken, agreementProxy, convictionApp } = await setupTests();

    //   const D = 10 ** 7;
    //   const proposalParam = {
    //     alpha: 0.9 * D,
    //     requiredConviction: 10 * D,
    //     numSecondPerStep: 5,
    //     tokenScalingFactor: 1

    //   }
    //   const figHash = agreementProxy.interface.encodeFunctionData(
    //     "createProposal",
    //     [superHookableToken.address, convictionApp.address, proposalParam, "0x"]
    //   );

    //   await sf.host.callAgreement(agreementProxy.address, figHash, "0x");
    //   await expect(await agreementProxy.getProposalLastConviction(
    //     superHookableToken.address,
    //     convictionApp.address,
    //     0))
    //     .to.equal(0);

    //   // let voteHash = agreementProxy.interface.encodeFunctionData(
    //   //   "vote",
    //   //   [superHookableToken.address, convictionApp.address, 1, 1 * D, "0x"]
    //   // );

    //   // await expect(sf.host.callAgreement(agreementProxy.address, voteHash, "0x"))
    //   //   .to.be.revertedWith("ProposalId does not exist.");

    //   let voteHash = agreementProxy.interface.encodeFunctionData(
    //     "vote",
    //     [superHookableToken.address, convictionApp.address, 0, 0.5 * D, "0x"]
    //   );


    //   // const ISuperfluid = await sf.contracts['ISuperfluid'];
    //   // console.log(ISuperfluid.abi);
    //   // console.log(waffle.provider);
    //   // const sfEtherjs = new hre.ethers.Contract(sf.host.address, ISuperfluid.abi, waffle.provider).connect(user1);
    //   // await expect(sfEtherjs.callAgreement(agreementProxy.address, voteHash, "0x"))
    //   //   .to.emit("ConvictionAgreement", "UserVoted")
    //   //   .withArgs(superHookableToken.address, convictionApp.address, 0, 0.5 * D);

    //   await sf.host.callAgreement(agreementProxy.address, voteHash, "0x");

    //   expect(await agreementProxy.getUserVotePercentage(superHookableToken.address,
    //     convictionApp.address,
    //     0,
    //     user1.address)).to.equal(0.5 * D);

    // });


    it("update conviction information while voting ", async () => {
      const { sf, superHookableToken, agreementProxy, convictionApp } = await setupTests();

      const D = 10 ** 7;
      const proposalParam = {
        alpha: 0.9 * D,
        requiredConviction: 1000 * D,
        numSecondPerStep: 10,
        tokenScalingFactor: 1

      }
      const figHash = agreementProxy.interface.encodeFunctionData(
        "createProposal",
        [superHookableToken.address, convictionApp.address, proposalParam, "0x"]
      );

      await sf.host.callAgreement(agreementProxy.address, figHash, "0x");
      await expect(await agreementProxy.getProposalLastConviction(
        superHookableToken.address,
        convictionApp.address,
        0))
        .to.equal(0);


      let voteHash = agreementProxy.interface.encodeFunctionData(
        "vote",
        [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
      );

      await sf.host.connect(user2).callAgreement(agreementProxy.address, voteHash, "0x");

      expect(await agreementProxy.getUserVotePercentage(superHookableToken.address,
        convictionApp.address,
        0,
        user2.address)).to.equal(1 * D);


      await ethers.provider.send("evm_increaseTime", [100]);

      console.log("Change Vote");

      voteHash = agreementProxy.interface.encodeFunctionData(
        "vote",
        [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
      );

      await sf.host.connect(user2).callAgreement(agreementProxy.address, voteHash, "0x");


      console.log("lastConviction");
      const latestConviction = await agreementProxy.getProposalLastConviction(
        superHookableToken.address,
        convictionApp.address,
        0)


      console.log(latestConviction.toString());
      // // expect(latestConviction.div(10 ** 4).toString()).to.equal("65132");

      console.log("===== Now create flow");

      //TODO Hook!!!!!!
      const IConstantFlowAgreementV1 = await sf.contracts['IConstantFlowAgreementV1'];
      const cfa = new Contract(sf.cfa._cfa.address, IConstantFlowAgreementV1.abi, ethers.provider);
      const cfaHash = cfa.interface.encodeFunctionData(
        "createFlow",
        [superHookableToken.address, user2.address, 1, "0x"]
      );

      console.log(superHookableToken.address);
      await sf.host.connect(user3).callAgreement(cfa.address, cfaHash, "0x");
      // await agreementProxy.onUpdateAgreement(superHookableToken.address, user2.address, ethers.utils.keccak256(ethers.utils.toUtf8Bytes("abcd")), [ethers.utils.keccak256(ethers.utils.toUtf8Bytes("abcd"))]);



      await ethers.provider.send("evm_increaseTime", [100]);

      console.log("refresh");

      await sf.host.callAgreement(agreementProxy.address,
        agreementProxy.interface.encodeFunctionData("refresh", [
          superHookableToken.address,
          convictionApp.address,
          0,
          "0x"
        ]),
        "0x"
      );


      console.log(
        (await agreementProxy.getProposalLastConviction(
          superHookableToken.address,
          convictionApp.address,
          0)
        ).toString());

      await ethers.provider.send("evm_increaseTime", [1000]);
      voteHash = agreementProxy.interface.encodeFunctionData(
        "vote",
        [superHookableToken.address, convictionApp.address, 0, 0.5 * D, "0x"]
      );

      await sf.host.connect(user3).callAgreement(agreementProxy.address, voteHash, "0x");

      console.log("Now upgrade=======");
      await superHookableToken.connect(user3).upgrade(ethers.utils.parseEther("50"));
    });


  })


})

const createErrorHandler = () => {
  return (err: any) => {
    if (err) throw err;
  }

};
