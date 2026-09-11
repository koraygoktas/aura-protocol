// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AuraVerifier
 * @notice ZK proof verifier mock for the AURA Protocol with replay and expiration protection.
 * @dev Reconstructs/verifies ZK-SNARK proof for risk scores and prevents proof theft.
 */
contract AuraVerifier {
    // Mapping to track used nonces for each user (proof replay protection)
    mapping(address => uint256) public userNonces;
    
    // Mapping to track used proof hashes (additional replay protection)
    mapping(bytes32 => bool) public usedProofs;

    // Error types
    error ProofExpired();
    error InvalidNonce();
    error ProofAlreadyUsed();
    error InvalidProofBinding();

    event ProofVerified(address indexed user, uint256 nonce, uint256 validUntil);
    event NonceIncremented(address indexed user, uint256 newNonce);

    /**
     * @notice Verifies a ZK-SNARK proof with replay and expiration protection.
     * @dev For EZKL compliance, publicInputs are:
     *      publicInputs[0] = borrower address (uint256 casted from address)
     *      publicInputs[1] = risk score (0 to 100)
     * @param proof The ZK-SNARK proof.
     * @param publicInputs The public inputs of the circuit.
     * @param validUntil Timestamp until which the proof is valid.
     * @param nonce Unique nonce for the user to prevent replay attacks.
     * @return bool True if the proof is valid.
     */
    function verifyProof(
        address borrower,
        bytes calldata proof, 
        uint256[] calldata publicInputs,
        uint256 validUntil,
        uint256 nonce
    ) external returns (bool) {
        // Check proof expiration
        if (block.timestamp > validUntil) {
            revert ProofExpired();
        }

        // Check nonce validity for the borrower
        if (nonce != userNonces[borrower]) {
            revert InvalidNonce();
        }

        // Check if proof was already used
        bytes32 proofHash = keccak256(abi.encodePacked(proof, publicInputs, borrower));
        if (usedProofs[proofHash]) {
            revert ProofAlreadyUsed();
        }

        // Basic proof validation
        if (proof.length == 0) return false;
        
        // Mock invalid proof detection
        if (keccak256(proof) == keccak256(abi.encodePacked("invalid-proof"))) {
            return false;
        }
        if (proof.length == 1 && proof[0] == 0x00) {
            return false;
        }

        // Must have at least 2 public inputs
        if (publicInputs.length < 2) {
            return false;
        }

        // Verify proof binding to borrower (front-running protection)
        address proofOwner = address(uint160(publicInputs[0]));
        if (proofOwner != borrower) {
            revert InvalidProofBinding();
        }

        // Verify risk score range (0-100)
        uint256 riskScore = publicInputs[1];
        if (riskScore > 100) {
            return false;
        }

        // Mark proof as used
        usedProofs[proofHash] = true;

        // Increment user nonce for next proof
        userNonces[borrower] = nonce + 1;
        
        emit ProofVerified(borrower, nonce, validUntil);
        emit NonceIncremented(borrower, nonce + 1);

        return true;
    }

    /**
     * @notice Get current nonce for a user.
     * @param user User address.
     * @return Current nonce value.
     */
    function getCurrentNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    /**
     * @notice Check if a proof hash has been used.
     * @param proofHash Hash of the proof.
     * @return bool True if proof has been used.
     */
    function isProofUsed(bytes32 proofHash) external view returns (bool) {
        return usedProofs[proofHash];
    }
}
