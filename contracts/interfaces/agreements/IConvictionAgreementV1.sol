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

    function refresh(
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

    function getProposalLastConviction(
        ISuperHookableToken token,
        address app,
        uint256 proposalId
    ) public view virtual returns (uint256);

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
