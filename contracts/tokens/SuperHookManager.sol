pragma solidity 0.7.6;

import {ISuperHookManager, ITokenObserver} from "../interfaces/tokens/ISuperHookManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SuperHookManager is ISuperHookManager, Ownable {
    mapping(address => ITokenObserver[]) public agreementHooks;
    mapping(address => ITokenObserver[]) public agreementStateHooks;
    ITokenObserver[] public balanceHooks;

    constructor() {
        transferOwnership(msg.sender);
    }

    function registerAgreementHook(ITokenObserver observer, address sender)
        external
        onlyOwner
    {
        agreementHooks[sender].push(observer);
    }

    function registerAgreemenStateHook(ITokenObserver observer, address sender)
        external
        onlyOwner
    {
        agreementStateHooks[sender].push(observer);
    }

    function registerBalanceHook(ITokenObserver observer) external onlyOwner {
        balanceHooks.push(observer);
    }

    function onMint(
        address token,
        address account,
        uint256 amount
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = balanceHooks;
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onMint(token, account, amount);
        }

        return true;
    }

    function onBurn(
        address token,
        address account,
        uint256 amount
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = balanceHooks;
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onBurn(token, account, amount);
        }
    }

    function onTransfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = balanceHooks;

        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onSend(token, from, amount);
            hooks[i].onReceive(token, to, amount);
        }

        return true;
    }

    function onSettleBalance(
        address token,
        address account,
        int256 resultAmount,
        int256 delta
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = balanceHooks;
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onSettle(token, account, resultAmount, delta);
        }

        return true;
    }

    function onCreateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = agreementHooks[sender];
        for (uint256 i; i < hooks.length; i++) {
            hooks[i].onCreateAgreement(token, sender, id, data);
        }
        return true;
    }

    function onUpdateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = agreementHooks[sender];
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onUpdateAgreement(token, sender, id, data);
        }
        return true;
    }

    function onUpdateAgreementState(
        address token,
        address sender,
        address account,
        uint256 id,
        bytes32[] calldata data
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = agreementStateHooks[sender];
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onUpdateAgreementState(token, sender, account, id, data);
        }
        return true;
    }

    function onTerminateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external override returns (bool) {
        ITokenObserver[] storage hooks = agreementHooks[sender];
        for (uint256 i = 0; i < hooks.length; i++) {
            hooks[i].onTerminateAgreement(token, sender, id, data);
        }
        return true;
    }
}
