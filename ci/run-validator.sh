#!/bin/bash

set -xeuo pipefail

# a private local network
P2P_NETWORK="private"
# a validator node configuration directory
CONFIG_DIR="$CELESTIA_HOME/.celestia-app"
# the names of the keys
USER_NAME=test1
VALIDATOR_NAME=validator1
# amounts of the coins for the keys
USER_COINS="500000000000000utia"
VALIDATOR_COINS="1000000000000000utia"
# a directory and the files shared with the bridge node
SHARED_DIR="/shared"
GENESIS_HASH_FILE="$SHARED_DIR/genesis_hash"
USER_KEY_FILE="$SHARED_DIR/$USER_NAME.keys"

# Saves the hash of the genesis node and the keys funded with the coins
# to the directory shared with the bridge node
provision_bridge_node() {
  local genesis_hash=""
  local user_address

  # Wait for the genesis block to be created and save a hash for the bridge
  while [[ -z "$genesis_hash" ]]; do
    # `|| echo` fallbacks to an empty string in case it's not ready
    genesis_hash="$(celestia-appd query block 1 | jq '.block_id.hash' || echo)"
    sleep 0.1
  done
  echo "Saving a genesis hash to $GENESIS_HASH_FILE"
  echo "$genesis_hash" > "$GENESIS_HASH_FILE"

  # Create a new user account
  echo "Creating a new keys for the test user"
  celestia-appd keys add "$USER_NAME" --keyring-backend "test"
  user_address="$(celestia-appd keys show "$USER_NAME" -a --keyring-backend="test")"

  # Send it the coins
  echo "Transfering coins to the test user"
  echo "y" | celestia-appd tx bank send \
    "$VALIDATOR_NAME" \
    "$user_address" \
    "$USER_COINS" \
    --fees 21000utia

  # And export it for the bridge
  echo "Exporting the keys for a test user to $USER_KEY_FILE"
  echo "password" | celestia-appd keys export "$USER_NAME" 2> "$USER_KEY_FILE"

  echo "Provisioning finished."
}

# Set up the validator for a private alone network.
# Based on
# https://github.com/celestiaorg/celestia-app/blob/main/scripts/single-node.sh
setup_private_validator() {
  local validator_addr

  # Initialize the validator
  celestia-appd init "$P2P_NETWORK" --chain-id "$P2P_NETWORK"
  # Derive a new private key for the validator
  celestia-appd keys add "$VALIDATOR_NAME" --keyring-backend="test"
  validator_addr="$(celestia-appd keys show "$VALIDATOR_NAME" -a --keyring-backend="test")"
  # Create a validator's genesis account for the genesis.json with an initial bag of coins
  celestia-appd add-genesis-account "$validator_addr" "$VALIDATOR_COINS"
  # Generate a genesis transaction that creates a validator with a self-delegation
  celestia-appd gentx "$VALIDATOR_NAME" 5000000000utia \
    --keyring-backend="test" \
    --chain-id "$P2P_NETWORK" \
    --evm-address 0x966e6f22781EF6a6A82BBB4DB3df8E225DfD9488 # private key: da6ed55cb2894ac2c9c10209c09de8e8b9d109b910338d5bf3d747a7e1fc9eb9
  # Collect the genesis transactions and form a genesis.json
  celestia-appd collect-gentxs

  # Set proper defaults and change ports
  # If you encounter: `sed: -I or -i may not be used with stdin` on MacOS you can mitigate by installing gnu-sed
  # https://gist.github.com/andre3k1/e3a1a7133fded5de5a9ee99c87c6fa0d?permalink_comment_id=3082272#gistcomment-3082272
  sed -i'.bak' 's|"tcp://127.0.0.1:26657"|"tcp://0.0.0.0:26657"|g' "$CONFIG_DIR/config/config.toml"
  sed -i'.bak' 's|"null"|"kv"|g' "$CONFIG_DIR/config/config.toml"
}

main() {
  # Configure stuff
  setup_private_validator
  # Spawn a job to provision a bridge node later
  provision_bridge_node &
  # Start the celestia-app
  echo "Configuration finished. Running a validator node..."
  celestia-appd start
}

main
