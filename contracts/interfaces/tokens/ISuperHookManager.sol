pragma solidity 0.7.6;

interface ISuperHookManager {
    function onMint(
        address token,
        address account,
        uint256 amount
    ) external returns (bool);

    function onBurn(
        address token,
        address account,
        uint256 amount
    ) external returns (bool);

    function onTransfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function onSettleBalance(
        address token,
        address account,
        int256 reusltAmount,
        int256 delta
    ) external returns (bool);

    function onCreateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external returns (bool);

    function onUpdateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external returns (bool);

    function onUpdateAgreementState(
        address token,
        address sender,
        address account,
        uint256 id,
        bytes32[] calldata data
    ) external returns (bool);

    function onTerminateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external returns (bool);
}

abstract contract ITokenObserver {
    function onSend(
        address token,
        address from,
        uint256 amount
    ) external virtual {}

    function onReceive(
        address token,
        address to,
        uint256 amount
    ) external virtual {}

    function onBurn(
        address token,
        address from,
        uint256 amount
    ) external virtual {}

    function onMint(
        address token,
        address to,
        uint256 amount
    ) external virtual {}

    function onSettle(
        address token,
        address account,
        int256 amount,
        int256 delta
    ) external virtual {}

    function onCreateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external virtual {}

    function onUpdateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external virtual {}

    function onUpdateAgreementState(
        address token,
        address sender,
        address account,
        uint256 id,
        bytes32[] calldata data
    ) external virtual {}

    function onTerminateAgreement(
        address token,
        address sender,
        bytes32 id,
        bytes32[] calldata data
    ) external virtual {}
}
