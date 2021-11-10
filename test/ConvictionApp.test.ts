import { expect } from "chai";
import hre, { deployments, waffle, ethers, web3 } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { BigNumberish, Contract, Wallet } from "ethers/lib/ethers";
import { resourceLimits } from "worker_threads";
import { ConstantFlowAgreementV1, ConvictionAgreementV1, ConvictionApp, SuperAppBase, SuperfluidToken, SuperHookableToken, SuperHookManager, TestApp } from "../typechain";
const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework.js");

const SuperfluidSDK = require("@superfluid-finance/js-sdk");

describe("ConvictionAgreementV1", async () => {

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

    const setupAgreement = async (sf: any, superHookableToken: SuperHookableToken,
        hookManager: SuperHookManager) => {
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

        const appFactory = await ethers.getContractFactory("ConvictionApp");
        const convictionApp = await appFactory.deploy(sf.host.address,
            agreementProxy.address,
            superHookableToken.address);

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
        const appAndAgreement = await setupAgreement(sf, tokenRelated.superHookableToken,
            tokenRelated.hookManager);

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


    describe("beforeAgreementCreated()", async () => {
        it("owner can create Proposal ", async () => {
            const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

            const content = await convictionApp.encodeData("hello app");

            await sf.host.callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "createProposal",
                    [superHookableToken.address, convictionApp.address, proposalParam, content, "0x"]
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
            expect(ethers.utils.toUtf8String(proposalData.data)).to.equal("hello app");

        });

        it("other cannot create Proposal ", async () => {
            const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

            const content = await convictionApp.encodeData("hello app");

            await expect(sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "createProposal",
                    [superHookableToken.address, convictionApp.address, proposalParam, content, "0x"]
                ),
                "0x")).to.be.revertedWith("Only owner can create proposal");


        });
    });

    describe("afterAgreementUpdated()", async () => {
        it("receive Passed proposal callback ", async () => {
            const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

            const content = await convictionApp.encodeData("hello app");

            await sf.host.callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "createProposal",
                    [superHookableToken.address, convictionApp.address,
                    { ...proposalParam, requiredConviction: 5 }
                        , content, "0x"]
                ),
                "0x");

            await sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "vote",
                    [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
                ), "0x");

            await ethers.provider.send('evm_increaseTime', [600]);
            await ethers.provider.send('evm_mine', []);


            await expect(sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "updateProposalConvictionAndStatus",
                    [superHookableToken.address, convictionApp.address, 0, "0x"]
                ), "0x"
            )).to.emit(convictionApp, "ProposalPassed");

        });


        it("receive User proposal callback ", async () => {
            const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

            const content = await convictionApp.encodeData("hello app");

            await sf.host.callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "createProposal",
                    [superHookableToken.address, convictionApp.address,
                    { ...proposalParam, requiredConviction: 5 }
                        , content, "0x"]
                ),
                "0x");

            await expect(await sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "vote",
                    [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
                ), "0x"))
                .to.emit(convictionApp, "UserVoted");


        });

    });




    describe("execute()", async () => {
        it("excute Passed proposal", async () => {
            const { sf, superHookableToken, agreementProxy, convictionApp, D, proposalParam } = await setupTests();

            const content = await convictionApp.encodeData("hello app");

            await sf.host.callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "createProposal",
                    [superHookableToken.address, convictionApp.address,
                    { ...proposalParam, requiredConviction: 5 }
                        , content, "0x"]
                ),
                "0x");

            await sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "vote",
                    [superHookableToken.address, convictionApp.address, 0, 1 * D, "0x"]
                ), "0x");

            await ethers.provider.send('evm_increaseTime', [600]);
            await ethers.provider.send('evm_mine', []);


            await expect(sf.host.connect(user2).callAgreement(agreementProxy.address,
                agreementProxy.interface.encodeFunctionData(
                    "updateProposalConvictionAndStatus",
                    [superHookableToken.address, convictionApp.address, 0, "0x"]
                ), "0x"
            )).to.emit(convictionApp, "ProposalPassed");

            await expect(convictionApp.execute(0)).to.emit(
                convictionApp, "ProposalExecuted");


        });


    });

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