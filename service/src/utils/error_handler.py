import re
from web3 import Web3
from web3.exceptions import ContractLogicError
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

    Args:
        error: The error object or message

    Returns:
        tuple: (error_name, error_code)
    """
    error_str = str(error)
    logger.debug(f"Processing error: {error_str}")

    # Case 1: Directly check for known hex codes in the error string
    hex_codes = re.findall(r'0x[0-9a-fA-F]+', error_str)
    for hex_code in hex_codes:
        if hex_code.lower() in ERROR_SIGNATURES:
            error_name = ERROR_SIGNATURES[hex_code.lower()]
            return error_name, hex_code

    # Case 2: Check for error data in dictionary format
    error_data = None
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

    # Case 3: Try to extract error data using regex if not found in args
    if not error_data:
        data_match = re.search(r"'data':\s*'([^']*)'", error_str)
        if data_match:
            error_data = data_match.group(1)

    # If we have error data, process it
    if error_data:
        logger.debug(f"Found error data: {error_data}")

        # Handle ASCII data like 'GGCl'
        if isinstance(error_data, str):
            # If it's already hex, use it directly
            if error_data.startswith('0x'):
                hex_data = error_data
            else:
                # Convert ASCII to hex
                try:
                    hex_data = '0x' + error_data.encode('utf-8').hex()
                    logger.debug(f"Converted ASCII '{error_data}' to hex: {hex_data}")
                except Exception as e:
                    logger.debug(f"Error converting ASCII to hex: {e}")
                    hex_data = None

            # Check if we have a valid hex to match against signatures
            if hex_data and hex_data.lower() in ERROR_SIGNATURES:
                error_name = ERROR_SIGNATURES[hex_data.lower()]
                return error_name, hex_data

        # Handle bytes data
        elif isinstance(error_data, bytes):
            try:
                hex_data = '0x' + error_data.hex()
                if hex_data.lower() in ERROR_SIGNATURES:
                    error_name = ERROR_SIGNATURES[hex_data.lower()]
                    return error_name, hex_data
            except Exception as e:
                logger.debug(f"Error converting bytes to hex: {e}")

    # Case 4: Check for error by name in the error string
    for error_name, _ in ERROR_SIGNATURES.items():
        error_name_str = ERROR_SIGNATURES[error_name]
        if error_name_str.lower() in error_str.lower():
            return error_name_str, error_name

    # No error type identified
    return None, None

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

    if error_name:
        return f"{error_name}:[{error_code}]"
    else:
        return f"Contract error: {str(error)}"
