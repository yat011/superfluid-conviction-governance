// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;
pragma abicoder v2;

import {AgreementBase} from "@superfluid-finance/ethereum-contracts/contracts/agreements/AgreementBase.sol";
import {ISuperHookableToken} from "../tokens/ISuperHookableToken.sol";
import {ITokenObserver} from "../tokens/ISuperHookManager.sol";

abstract contract IConvictionAgreementV1 is AgreementBase, ITokenObserver {
    struct ProposalParam {
        uint256 alpha;
        uint256 requiredConviction;
        uint256 numSecondPerStep;
        uint256 tokenScalingFactor;
    }
    enum ProposalStatus {
        Active,
        Pass,
        Insolvent
    }

    struct ProposalData {
        uint256 proposalId;
        address app;
        ISuperHookableToken governToken;
        uint256 lastTimeStamp;
        uint256 lastConviction;
        uint256 amount; //scaled token amount
        int256 flowRate; //scaled, per step instead of second
        ProposalStatus status;
        ProposalParam param;
    }
    struct AppProposalId {
        address app;
        uint256 proposalId;
    }

    /// @dev ISuperAgreement.agreementType implementation
    function agreementType() external view override returns (bytes32) {
        return keccak256("hackathon.ConvictionAgreement.v1");
    }

    function createProposal(
        ISuperHookableToken token,
        address app,
        ProposalParam calldata param,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    // onlyActiveProposal(app, token, proposalId)
    function vote(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        uint256 percentage,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    function updateProposalConvictionAndStatus(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    function getUserVotePercentage(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (uint256);

    function getUserVoteAmount(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (uint256);

    function getUserVoteFlow(
        ISuperHookableToken token,
        address app,
        uint256 proposalId,
        address user
    ) public view virtual returns (int256);

    function getVotingProposalsByAppUser(
        ISuperHookableToken token,
        address app,
        address user
    ) public view virtual returns (uint256[] memory);

    function getVotingProposalsByUser(ISuperHookableToken token, address user)
        public
        view
        virtual
        returns (AppProposalId[] memory);

    function getProposalLastConviction(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view virtual returns (uint256);

    function getProposal(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view virtual returns (ProposalData memory);

    function calculateConviction(
        uint256 numStep,
        uint256 initConviction,
        uint256 amount,
        int256 flowRate,
        uint256 alpha
    ) public view virtual returns (uint256);

    function getAllBalance(ISuperHookableToken token, address account)
        public
        virtual
        returns (int256);
}
