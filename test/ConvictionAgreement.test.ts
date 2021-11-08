import { expect } from "chai";
import hre, { deployments, waffle, ethers, web3 } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { ConstantFlowAgreementV1Helper } from "@superfluid-finance/js-sdk";
import { SSL_OP_NO_QUERY_MTU } from "constants";
import { Result } from "@ethersproject/abi/lib/interface";
const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework.js");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");

const SuperfluidSDK = require("@superfluid-finance/js-sdk");

describe("SuperHookableToken", async () => {
    // const [user1, user2, user3] = await ethers.getSigners();
    const [user1, user2, user3] = waffle.provider.getWallets();
    const abiCoder = new ethers.utils.AbiCoder();

    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();

        const testTokenFactory = await ethers.getContractFactory("TestToken");
        const superTokenFactory = await ethers.getContractFactory("SuperHookableToken");

        const testToken = await testTokenFactory.deploy("HiToken", "Hi", 18);

        const mathUtilsFactory = await ethers.getContractFactory("mathUtils");
        const mathUtils = await mathUtilsFactory.deploy()

        const agreementFactory = await ethers.getContractFactory("ConvictionAgreement", {
            libraries: {
                "mathUtils": mathUtils.address
            }
        });
        return {
            "testToken": testToken,
            "superTokenFactory": superTokenFactory,
            "agreementFactory": agreementFactory
        };
    });

    it("setup", async () => {
        const { testToken, superTokenFactory } = await setupTests();
    });


    describe("upgrade", async () => {

        it("can ..", async () => {
            const { testToken, superTokenFactory, agreementFactory } = await setupTests();


            /// agreement


            const agreement = await agreementFactory.deploy();

            const D = 10000000;
            const numStep = 3;
            const amount = 1 * D;
            const flowrate = 1 * D;
            const alpha = 0.9 * D;
            const result = await agreement.calculateConviction(numStep, 0, amount, flowrate, alpha);

            console.log("result");
            console.log(result.toString());

            let result2 = await agreement.getMaxConvictionStep(0, 100 * D, -1 * D, alpha);
            console.log(result2.toString());

            result2 = await agreement.getMaxConvictionStep(0, 100 * D, 1 * D, alpha);
            console.log(result2.toString());

            result2 = await agreement.getMaxConvictionStep(100 * D, 100 * D, 0, alpha);
            console.log(result2.toString());

            result2 = await agreement.getMaxConvictionStep(100 * D, 0, 0, alpha);
            console.log(result2.toString());
        });
    })


})

const createErrorHandler = () => {
    return (err: any) => {
        if (err) throw err;
    }

};
