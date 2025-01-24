import { ethers } from "ethers";
import dotenv from "dotenv";
import { CESSupergroupABI } from "./abis/CESSupergroup";
import * as fs from "fs";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY_GNOSIS || "";
const RPC_URL = process.env.RPC_URL_GNOSIS || "";

async function main() {
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  // Load supergroup address from file
  const supergroupAddress = fs.readFileSync(
    "./deployments/CESSupergroup-gnosis.txt",
    "utf8",
  );

  // Initialize contract instances
  const supergroup = new ethers.Contract(
    supergroupAddress,
    CESSupergroupABI,
    wallet,
  );

  // Read state
  const owner = await supergroup.owner();
  const service = await supergroup.service();
  const mintFee = await supergroup.mintFee();
  const feeCollection = await supergroup.feeCollection();
  const redemptionBurnRate = await supergroup.redemptionBurnRate();
  const requireOperator = await supergroup.requireOperator();
  const returnGroupCirclesToSender =
    await supergroup.returnGroupCirclesToSender();
  const operators = await supergroup.getOperators();

  console.log("Supergroup State:");
  console.log("Owner:", owner);
  console.log("Service:", service);
  console.log("Mint Fee:", mintFee.toString());
  console.log("Fee Collection:", feeCollection);
  console.log("Redemption Burn Rate:", redemptionBurnRate.toString());
  console.log("Require Operator:", requireOperator);
  console.log("Return Group Circles to Sender:", returnGroupCirclesToSender);
  console.log("Operators:", operators);

  // Owner functions

  // Set service
  const setServiceTx = await supergroup.setService(
    ethers.constants.AddressZero,
  );
  await setServiceTx.wait();

  // Trust address
  const trustTx = await supergroup.trust(ethers.constants.AddressZero, 0);
  await trustTx.wait();

  // Set mint fee
  const setMintFeeTx = await supergroup.setMintFee(
    0,
    ethers.constants.AddressZero,
  );
  await setMintFeeTx.wait();

  // Set redemption burn rate
  const setRedemptionBurnTx = await supergroup.setRedemptionBurn(0);
  await setRedemptionBurnTx.wait();

  // Set require operators
  const setRequireOperatorsTx = await supergroup.setRequireOperators(false);
  await setRequireOperatorsTx.wait();

  // Set return group circles
  const setReturnGroupCirclesTx =
    await supergroup.setReturnGroupCirclesToSender(false);
  await setReturnGroupCirclesTx.wait();

  // Set operator
  const setOperatorTx = await supergroup.setAuthorizedOperator(
    ethers.constants.AddressZero,
    false,
  );
  await setOperatorTx.wait();

  // Update metadata
  const updateMetadataDigestTx = await supergroup.updateMetadataDigest(
    ethers.constants.HashZero,
  );
  await updateMetadataDigestTx.wait();

  // Register short name
  const registerShortNameTx = await supergroup.registerShortName();
  await registerShortNameTx.wait();

  // Batch operations
  const trustBatchTx = await supergroup.trustBatch(
    [ethers.constants.AddressZero],
    0,
  );
  await trustBatchTx.wait();

  const safeBatchTransferTx = await supergroup.safeBatchTransferFrom(
    ethers.constants.AddressZero,
    ethers.constants.AddressZero,
    [0],
    [0],
    "0x",
  );
  await safeBatchTransferTx.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
