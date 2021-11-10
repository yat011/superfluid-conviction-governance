# Superfluid Conviction Voting with Constant Flow Streaming Support

This hackathon work provides a generic conviction voting tool, powered by superfluid framework, to enable the easy adoption of conviction voting. 

Our conviction voting implementation can automatically react to any constant Superfluid streaming changes. In other words, user can continuously increase/decrease their conviction voting power towards their favourite proposals while they are sending/receiving the governance tokens without extra transaction, lockup and staking.

# Run and Test Locally
```
yarn
npx hardhat test
```

# Methodology
Please find the detail here .....

# Components
- ConvictionAgreement: This implements the core logic which handles the conviction calaution, proposal creation, user voting, and the changes of proposal's status. Execution of proposal is not included, and depends on DAO's application.


- SuperHookableToken and HookManager: Used to observe any trnsfer/mint/burn/agremment update of the token in order to the conviction state accordingly.

- ConvictionApp: Example SuperApp which use ConvictionAgreement.


# Future works
e.g. Optimate gas fee
