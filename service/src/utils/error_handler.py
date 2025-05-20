import re
from web3 import Web3
from web3.exceptions import ContractLogicError
from tenacity import retry, stop_after_attempt, wait_fixed, retry_if_exception_type, RetryError
from web3.exceptions import Web3RPCError
import logging

logger = logging.getLogger(__name__)

# Error signatures mapping
ERROR_SIGNATURES = {
    "0x4747436c": "OrderAlreadySettled",
    "0x590eda20": "OrderUidIsTheSame",
    "0x187b2dad": "OrderNotYetFilled",
    "0x076bfeeb": "LBPAlreadyCreated",
    "0x660542cc": "BackingAssetBalanceInsufficient"
}

# Mapping of error names to status codes - this will be useful for the LBP processor
ERROR_TO_STATUS = {
    "OrderAlreadySettled": "order_already_settled",
    "OrderUidIsTheSame": "order_uid_same",
    "OrderNotYetFilled": "order_not_yet_filled",
    "LBPAlreadyCreated": "lbp_already_created",
    "BackingAssetBalanceInsufficient": "insufficient_balance"
}


def identify_contract_error(error):
    """
    Identify contract error type from different error formats.
    Handle both ContractLogicError/ContractCustomError and Web3RPCError gracefully.

    Args:
        error: The error object or message

    Returns:
        tuple: (error_name, error_code)
    """
    error_str = str(error)
    error_type = type(error).__name__
    logger.debug(f"Processing error: {error_str} of type {error_type}")

    try:
        # Check the error type
        if hasattr(error, '__module__') and 'web3.exceptions' in getattr(error, '__module__', ''):
            if error_type == 'Web3RPCError':
                # Special handling for Web3RPCError
                error_info = _handle_web3_rpc_error(error)
                if error_info[0] is None:  # If no specific error identified
                    return _enhanced_generic_error(error)
                return error_info
            elif error_type in ('ContractLogicError', 'ContractCustomError'):
                # Handle ContractLogicError/ContractCustomError
                error_info = _handle_contract_custom_error(error)
                if error_info[0] is None:  # If no specific error identified
                    return _enhanced_generic_error(error)
                return error_info
            else:
                # Handle other Web3 exceptions
                logger.warning(f"Unhandled Web3 exception type: {error_type}")
                return _enhanced_generic_error(error)
        else:
            # Generic error handling for non-Web3 errors
            error_info = _handle_generic_error(error)
            if error_info[0] is None:  # If no specific error identified
                return _enhanced_generic_error(error)
            return error_info

    except Exception as e:
        # Catch any exception in the error handling itself to prevent service disruption
        logger.error(f"Error while processing exception: {str(e)}")
        return "ErrorProcessingFailure", str(e)[:40]

def extract_error_code(error, web3=None):
    """
    Legacy compatibility function that works the same as identify_contract_error.

    Args:
        error: The error object or message
        web3: The Web3 instance (optional, not used but kept for compatibility)

    Returns:
        tuple: (error_name, hex_code)
    """
    return identify_contract_error(error)

def get_status_from_error_name(error_name):
    """
    Convert an error name to a status code for validation results.

    Args:
        error_name: The name of the error

    Returns:
        str: The corresponding status code or 'contract_error' if not found
    """
    if not error_name:
        return "contract_error"

    return ERROR_TO_STATUS.get(error_name, "contract_error")

def format_contract_error(error):
    """
    Format a contract error for display, with error code.

    Args:
        error: The error object

    Returns:
        str: Formatted error message
    """
    error_name, error_code = identify_contract_error(error)
    return f"{error_name}:[{error_code}]"

def _handle_web3_rpc_error(error):
    """Handle Web3RPCError specifically"""
    logger.debug(f"Handling Web3RPCError: {error}")

    # Store error info for return or logging
    error_name = None
    error_code = None
    should_retry = False

    # Check if this is a generic RPC error that should be retried
    if hasattr(error, 'args') and error.args and isinstance(error.args[0], dict):
        error_dict = error.args[0]
        if 'code' in error_dict:
            error_code = error_dict['code']
            # These error codes typically indicate transient issues that should be retried
            retry_error_codes = [-32603, -32002, -32001, -32015, -32010, -32000, -32004, -32005]
            if error_code in retry_error_codes:
                should_retry = True
                logger.info(f"RPC error code {error_code} detected - will be retried")

    # Web3RPCErrors often have the error details in the response object
    if hasattr(error, 'args') and error.args:
        try:
            # Try to extract the error data
            if isinstance(error.args[0], dict):
                error_dict = error.args[0]

                # Check for data field in the RPC error response
                if 'data' in error_dict:
                    error_data = error_dict['data']
                    logger.debug(f"Found RPC error data: {error_data}")

                    # Handle different data formats
                    if isinstance(error_data, str):
                        # Handle ASCII selector like 'GGCl'
                        if not error_data.startswith('0x'):
                            try:
                                hex_data = '0x' + error_data.encode('utf-8').hex()
                                logger.debug(f"Converted ASCII '{error_data}' to hex: {hex_data}")

                                if hex_data.lower() in ERROR_SIGNATURES:
                                    error_name = ERROR_SIGNATURES[hex_data.lower()]
                                    error_code = hex_data
                            except Exception as e:
                                logger.debug(f"Error converting ASCII to hex: {e}")
                        else:
                            # Already hex format
                            if error_data.lower() in ERROR_SIGNATURES:
                                error_name = ERROR_SIGNATURES[error_data.lower()]
                                error_code = error_data
        except Exception as e:
            logger.debug(f"Error processing Web3RPCError args: {e}")

    # If this error should be retried, re-raise it
    if should_retry:
        logger.info(f"Re-raising Web3RPCError for retry")
        raise error

    # If we have valid error info, return it
    if error_name:
        return error_name, error_code

    # If no specific error was identified, return a generic RPC error with the code
    if error_code:
        return f"RPCError({error_code})", str(error_code)

    # Last resort - generic error with the string representation
    truncated_msg = str(error)[:50] + ("..." if len(str(error)) > 40 else "")
    return "Web3Error", truncated_msg

def _handle_contract_custom_error(error):
    """Handle ContractLogicError/ContractCustomError specifically"""
    logger.debug(f"Handling Contract Custom Error: {error}")

    if hasattr(error, 'args') and error.args:
        # Handle tuple args format like ('0x4747436c', '0x4747436c')
        if isinstance(error.args[0], tuple):
            for item in error.args[0]:
                if isinstance(item, str) and item.startswith('0x'):
                    if item.lower() in ERROR_SIGNATURES:
                        error_name = ERROR_SIGNATURES[item.lower()]
                        return error_name, item

        # Handle dictionary format with 'data' field
        if isinstance(error.args[0], dict) and 'data' in error.args[0]:
            error_data = error.args[0]['data']

            # Process the data field
            if isinstance(error_data, str):
                if error_data.startswith('0x'):
                    # Already hex format
                    hex_data = error_data
                else:
                    # Convert ASCII to hex
                    try:
                        hex_data = '0x' + error_data.encode('utf-8').hex()
                    except Exception as e:
                        logger.debug(f"Error converting ASCII to hex: {e}")
                        hex_data = None

                if hex_data and hex_data.lower() in ERROR_SIGNATURES:
                    error_name = ERROR_SIGNATURES[hex_data.lower()]
                    return error_name, hex_data

    # If specific extraction failed, fall back to regex
    return _handle_generic_error(error)

def _handle_generic_error(error):
    """Generic error handling using regex and string parsing"""
    error_str = str(error)
    logger.debug(f"Performing generic error handling for: {error_str}")

    # Look for hex codes directly in the error string
    hex_codes = re.findall(r'0x[0-9a-fA-F]+', error_str)
    for hex_code in hex_codes:
        if hex_code.lower() in ERROR_SIGNATURES:
            error_name = ERROR_SIGNATURES[hex_code.lower()]
            return error_name, hex_code

    # Look for 'data' field using regex
    data_match = re.search(r"'data':\s*'([^']*)'", error_str)
    if data_match:
        error_data = data_match.group(1)
        logger.debug(f"Found error data via regex: {error_data}")

        # Handle hex or ASCII data
        if error_data.startswith('0x'):
            hex_data = error_data
        else:
            try:
                hex_data = '0x' + error_data.encode('utf-8').hex()
            except Exception as e:
                logger.debug(f"Error converting regex-found data to hex: {e}")
                hex_data = None

        if hex_data and hex_data.lower() in ERROR_SIGNATURES:
            error_name = ERROR_SIGNATURES[hex_data.lower()]
            return error_name, hex_data

    # Check for error by name in the error string as last resort
    for hex_code, error_name in ERROR_SIGNATURES.items():
        if error_name.lower() in error_str.lower():
            return error_name, hex_code

    # No error type identified, but we'll try to enhance it in the calling function
    return None, None

def _enhanced_generic_error(error):
    """
    Enhanced generic error handling that always returns something meaningful
    instead of (None, None)
    """
    error_str = str(error)

    # Try to extract error code if present (common in RPC errors)
    code_match = re.search(r"'code':\s*(-?\d+)", error_str)
    if code_match:
        error_code = code_match.group(1)
        # Common RPC error codes and their descriptions
        rpc_error_names = {
            "-32700": "ParseError",
            "-32600": "InvalidRequest",
            "-32601": "MethodNotFound",
            "-32602": "InvalidParams",
            "-32603": "InternalError",
            "-32000": "ExecutionError",
            "-32001": "ResourceNotFound",
            "-32002": "ResourceUnavailable",
            "-32003": "TransactionRejected",
            "-32004": "MethodNotSupported",
            "-32005": "RateLimited",
        }
        error_name = rpc_error_names.get(error_code, f"RPCError({error_code})")
        return error_name, error_code

    # Look for common error phrases
    common_errors = [
        ("timeout", "TimeoutError"),
        ("connection", "ConnectionError"),
        ("network", "NetworkError"),
        ("gas", "GasError"),
        ("nonce", "NonceError"),
        ("underpriced", "UnderpricedError"),
        ("rate limit", "RateLimitError"),
        ("insufficient funds", "InsufficientFunds"),
        ("unauthorized", "Unauthorized"),
        ("reverted", "TransactionReverted"),
        ("out of gas", "OutOfGasError"),
        ("execution reverted", "ExecutionReverted")
    ]

    for keyword, error_type in common_errors:
        if keyword.lower() in error_str.lower():
            # Return the identified error type with a truncated error message as the "code"
            # Limit to 40 chars to keep it reasonable
            truncated_msg = error_str[:40] + ("..." if len(error_str) > 40 else "")
            return error_type, truncated_msg

    # If we still can't identify anything specific, return a generic error with the message
    truncated_msg = error_str[:40] + ("..." if len(error_str) > 40 else "")
    return "UnknownError", truncated_msg

def web3_rpc_retry(func):
    """
    Decorator to retry functions when they encounter Web3RPCError.
    Uses a fixed wait of 5 seconds between attempts and stops after 3 attempts.
    """
    @retry(
        retry=retry_if_exception_type(Web3RPCError),
        stop=stop_after_attempt(3),
        wait=wait_fixed(5),
        reraise=True,
        before_sleep=lambda retry_state: logger.info(
            f"Web3 RPC error, retrying in 5s... (attempt {retry_state.attempt_number}/3)"
        )
    )
    def wrapper(*args, **kwargs):
        return func(*args, **kwargs)
    return wrapper
