UPDATE block_rewards
SET block_number = b.number
FROM blocks b
WHERE b.hash = block_rewards.block_hash
AND block_rewards.block_number IS NULL;