#!/usr/bin/env bash
#====================================================
# pro2-setup.sh
# Professional installer & configurator for Infernet
#====================================================

set -euo pipefail
IFS=$'\n\t'

# Color definitions
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

# Trap errors
trap 'echo -e "${RED}[ERROR] Script failed at line $LINENO${NC}"; exit 1' ERR

# Execution helper
exec_cmd() {
  echo -e "${BLUE}[EXEC]${NC} $*"
  sleep 0.5
  if ! "$@"; then
    echo -e "${RED}[FAIL]${NC} Command failed: $*"
    exit 1
  fi
}

# Ignorable execution (allows failure)
exec_ign() {
  echo -e "${YELLOW}[EXEC-IGN]${NC} $*"
  sleep 0.5
  "$@" || echo -e "${YELLOW}[WARN] Ignored failure for: $*${NC}"
}

# 1. Clone starter repository
echo -e "${GREEN}Cloning Infernet starter repository...${NC}"
exec_cmd git clone --quiet https://github.com/ritual-net/infernet-container-starter "$HOME/infernet-container-starter"

# 2. Run container deployment (ignore runtime errors)
echo -e "${GREEN}Deploying container (detached mode)...${NC}"
pushd "$HOME/infernet-container-starter" >/dev/null
exec_ign make deploy-container >/dev/null 2>&1
popd >/dev/null

# 3. JSON configuration replacements
echo -e "${GREEN}Configuring node settings...${NC}"
CONFIG_DEPLOY="$HOME/infernet-container-starter/deploy/config.json"
CONFIG_CONTAINER="$HOME/infernet-container-starter/projects/hello-world/container/config.json"
SCRIPT_DEPLOY="$HOME/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol"

# Base URL & synchronization updates
sed -i \
  -e 's|http://host.docker.internal:8545|https://mainnet.base.org/|g' \
  -e 's/"trail_head_blocks": *0/"trail_head_blocks": 3/' \
  -e 's/"sleep": *1\.5/"sleep": 3/' \
  -e 's/"sync_period": *1/"sync_period": 30/' \
  "$CONFIG_DEPLOY"

# 4. User inputs
read -rp "Enter Current Registry address (see here https://tinyurl.com/3nk27sy4): " REG_ADDR
read -rp "Enter Your wallet Private Key (must start with 0x and Please keep 20 USD ETH in your wallet.): " PRIV_KEY
read -rp "Enter current node version (see here https://tinyurl.com/m2vfwznd ) : " NODE_VER

# Apply registry address
sed -i "s/0x663F3ad617193148711d28f5334eE4Ed07016602/$REG_ADDR/g" \
  "$CONFIG_DEPLOY" \
  "$SCRIPT_DEPLOY"

echo -e "${GREEN}Replaced registry address in config & deploy script.${NC}"

# Apply private key
sed -i "s@0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d@$PRIV_KEY@g" \
  "$CONFIG_DEPLOY" \
  "$CONFIG_CONTAINER"

echo -e "${GREEN}Inserted private key into config files.${NC}"

# Apply node version in docker-compose
docker_compose_file="$HOME/infernet-container-starter/deploy/docker-compose.yaml"
sed -i "s/1\.3\.1/$NODE_VER/" "$docker_compose_file"
echo -e "${GREEN}Updated node version to $NODE_VER in docker-compose.${NC}"

# 5. Update Makefile for contracts
makefile_contracts="$HOME/infernet-container-starter/projects/hello-world/contracts/Makefile"
sed -i "s|RPC_URL *=.*|RPC_URL = https://mainnet.base.org/|" "$makefile_contracts"
sed -i "s|SENDER *=.*|SENDER = $PRIV_KEY|" "$makefile_contracts"
echo -e "${GREEN}Patched Makefile with RPC_URL and sender key.${NC}"

# 6. Restart containers
echo -e "${GREEN}Restarting Infernet containers...${NC}"
exec_cmd docker compose -f "$docker_compose_file" down
exec_cmd docker compose -f "$docker_compose_file" up -d

# 7. Install Foundry
echo -e "${GREEN}Installing Foundry...${NC}"
exec_cmd mkdir -p "$HOME/foundry"
pushd "$HOME/foundry" >/dev/null
exec_cmd curl -sL https://foundry.paradigm.xyz | bash
popd >/dev/null
exec_cmd source ~/.bashrc
exec_cmd foundryup

# 8. Deploy consumer contract
echo -e "${GREEN}Deploying consumer contract...${NC}"
exec_cmd docker compose -f "$docker_compose_file" down
exec_cmd docker compose -f "$docker_compose_file" up -d
pushd "$HOME/infernet-container-starter" >/dev/null
exec_cmd project=hello-world make deploy-contracts
popd >/dev/null

# 9. Update consumer call script
CALL_SCRIPT="$HOME/infernet-container-starter/projects/hello-world/contracts/script/CallContract.s.sol"
# Extract address from logs (assumes last Contract Address: 0x... in stdout)
CONTRACT_ADDR=$(grep -oE "Contract Address: 0x[0-9a-fA-F]+" <<< "$(project=hello-world make deploy-contracts)" | tail -1 | awk '{print $3}')
if [[ -z "$CONTRACT_ADDR" ]]; then
  echo -e "${RED}[ERROR] Failed to parse contract address.${NC}" && exit 1
fi
sed -i "s/0x13D69Cf7d6CE4218F646B759Dcf334D82c023d8e/$CONTRACT_ADDR/" "$CALL_SCRIPT"
echo -e "${GREEN}Updated call script with contract address $CONTRACT_ADDR.${NC}"

# 10. Call contract
echo -e "${GREEN}Calling contract...${NC}"
pushd "$HOME/infernet-container-starter" >/dev/null
exec_cmd project=hello-world make call-contract
popd >/dev/null

# Final message
echo -e "${GREEN}Congrats! You have successfully set up a Ritual Infernet Node and created an on-chain subscription request.\nView transactions at: https://basescan.org/${NC}"
