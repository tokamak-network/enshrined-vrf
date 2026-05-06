#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYER_ADDR:?set DEPLOYER_ADDR}"

L1_CHAIN_ID="${L1_CHAIN_ID:-11155111}"
L2_CHAIN_ID="${L2_CHAIN_ID:-901005}"
L2_CHAIN_ID_HEX="${L2_CHAIN_ID_HEX:-$(printf "0x%064x" "$L2_CHAIN_ID")}"
ARTIFACTS_LOCATOR="${ARTIFACTS_LOCATOR:-embedded}"

BATCHER_ADDR="${BATCHER_ADDR:-$DEPLOYER_ADDR}"
PROPOSER_ADDR="${PROPOSER_ADDR:-$DEPLOYER_ADDR}"
CHALLENGER_ADDR="${CHALLENGER_ADDR:-$DEPLOYER_ADDR}"
SYSTEM_CONFIG_OWNER_ADDR="${SYSTEM_CONFIG_OWNER_ADDR:-$DEPLOYER_ADDR}"
L1_PROXY_ADMIN_OWNER_ADDR="${L1_PROXY_ADMIN_OWNER_ADDR:-$DEPLOYER_ADDR}"
L2_PROXY_ADMIN_OWNER_ADDR="${L2_PROXY_ADMIN_OWNER_ADDR:-$DEPLOYER_ADDR}"
UNSAFE_BLOCK_SIGNER_ADDR="${UNSAFE_BLOCK_SIGNER_ADDR:-$DEPLOYER_ADDR}"
FEE_VAULT_RECIPIENT_ADDR="${FEE_VAULT_RECIPIENT_ADDR:-$DEPLOYER_ADDR}"
CHAIN_FEES_RECIPIENT_ADDR="${CHAIN_FEES_RECIPIENT_ADDR:-$DEPLOYER_ADDR}"

cat <<EOF_INTENT
configType = "custom"
opDeployerVersion = "dev"
l1ChainID = $L1_CHAIN_ID
fundDevAccounts = true
useInterop = false
l1ContractsLocator = "$ARTIFACTS_LOCATOR"
l2ContractsLocator = "$ARTIFACTS_LOCATOR"

[superchainRoles]
  SuperchainProxyAdminOwner = "$DEPLOYER_ADDR"
  SuperchainGuardian = "$DEPLOYER_ADDR"
  ProtocolVersionsOwner = "$DEPLOYER_ADDR"
  Challenger = "$CHALLENGER_ADDR"

[globalDeployOverrides]
  l2GenesisKarstTimeOffset = "0x0"
  l2GenesisInteropTimeOffset = "0x0"
  l2GenesisEnshrainedVRFTimeOffset = "0x0"

[[chains]]
  id = "$L2_CHAIN_ID_HEX"
  baseFeeVaultRecipient = "$FEE_VAULT_RECIPIENT_ADDR"
  l1FeeVaultRecipient = "$FEE_VAULT_RECIPIENT_ADDR"
  sequencerFeeVaultRecipient = "$FEE_VAULT_RECIPIENT_ADDR"
  operatorFeeVaultRecipient = "$FEE_VAULT_RECIPIENT_ADDR"
  eip1559DenominatorCanyon = 250
  eip1559Denominator = 50
  eip1559Elasticity = 6
  gasLimit = 60000000
  operatorFeeScalar = 0
  operatorFeeConstant = 0
  useRevenueShare = false
  chainFeesRecipient = "$CHAIN_FEES_RECIPIENT_ADDR"

  [chains.roles]
    l1ProxyAdminOwner = "$L1_PROXY_ADMIN_OWNER_ADDR"
    l2ProxyAdminOwner = "$L2_PROXY_ADMIN_OWNER_ADDR"
    systemConfigOwner = "$SYSTEM_CONFIG_OWNER_ADDR"
    unsafeBlockSigner = "$UNSAFE_BLOCK_SIGNER_ADDR"
    batcher = "$BATCHER_ADDR"
    proposer = "$PROPOSER_ADDR"
    challenger = "$CHALLENGER_ADDR"
EOF_INTENT
