import os
import json
import logging
from typing import Dict, Any, Optional
from datetime import datetime

logger = logging.getLogger(__name__)

class StateManager:
    """
    Handles persistence and recovery of application state.
    Provides methods to save, load, and manage application state across restarts.
    """

    def __init__(self, state_file: str = "algorithm_state.json", state_dir: str = ""):
        """
        Initialize the StateManager.

        Args:
            state_file: Name of the file to store state
            state_dir: Directory to store state files (empty for current directory)
        """
        self.state_dir = state_dir
        self.state_file = os.path.join(state_dir, state_file) if state_dir else state_file
        logger.info(f"StateManager initialized with state file: {self.state_file}")

    def save(self, state_data: Dict[str, Any]) -> bool:
        """
        Save state data to disk.

        Args:
            state_data: Dictionary of state data to save

        Returns:
            bool: True if save was successful, False otherwise
        """
        try:
            # Ensure the state directory exists
            if self.state_dir and not os.path.exists(self.state_dir):
                os.makedirs(self.state_dir)

            # Add timestamp to state data
            data_to_save = state_data.copy()
            data_to_save['save_timestamp'] = datetime.now().isoformat()

            # Write to file
            with open(self.state_file, 'w') as f:
                json.dump(data_to_save, f, indent=2)

            logger.debug(f"State saved successfully: {list(state_data.keys())}")
            return True

        except Exception as e:
            logger.error(f"Failed to save state: {str(e)}")
            return False

    def load(self) -> Optional[Dict[str, Any]]:
        """
        Load state data from disk.

        Returns:
            Dict containing state data or None if loading failed
        """
        try:
            if not os.path.exists(self.state_file):
                logger.info(f"No state file found at {self.state_file}")
                return None

            with open(self.state_file, 'r') as f:
                state_data = json.load(f)

            logger.info(f"State loaded from {self.state_file}: {list(state_data.keys())}")
            return state_data

        except Exception as e:
            logger.error(f"Failed to load state: {str(e)}")
            return None

    def clear(self) -> bool:
        """
        Clear saved state by deleting the state file.

        Returns:
            bool: True if clearing was successful, False otherwise
        """
        try:
            if os.path.exists(self.state_file):
                os.remove(self.state_file)
                logger.info(f"State file {self.state_file} has been deleted")
                return True
            else:
                logger.warning(f"No state file found at {self.state_file}")
                return False

        except Exception as e:
            logger.error(f"Failed to clear state: {str(e)}")
            return False

    def get_state_age(self) -> Optional[float]:
        """
        Get the age of the state file in seconds.

        Returns:
            float: Age in seconds or None if file doesn't exist
        """
        try:
            if not os.path.exists(self.state_file):
                return None

            file_mtime = os.path.getmtime(self.state_file)
            age_seconds = datetime.now().timestamp() - file_mtime
            return age_seconds

        except Exception as e:
            logger.error(f"Failed to get state age: {str(e)}")
            return None
