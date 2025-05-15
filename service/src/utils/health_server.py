from fastapi import FastAPI
from fastapi.responses import JSONResponse
import logging
from typing import Optional
import threading
import uvicorn

from algorithm.trust_management import TrustManagementAlgorithm
from clients.nethermind import NethermindClient
from clients.screening import ScreeningClient

logger = logging.getLogger(__name__)
app = FastAPI()

trust_algorithm: Optional[TrustManagementAlgorithm] = None
nethermind_client: Optional[NethermindClient] = None
screening_client: Optional[ScreeningClient] = None

@app.get("/health")
async def health_check():
    try:
        health = {
            'status': 'healthy',
            'details': {}
        }

        if nethermind_client:
            rpc_health = nethermind_client.check_health()
            health['details']['rpc'] = rpc_health
            if rpc_health.get('status') != 'healthy':
                health['status'] = rpc_health.get('status', 'unhealthy')

        if trust_algorithm:
            algo_health = trust_algorithm.check_health()
            health['details']['algorithm'] = algo_health
            if algo_health.get('block_lag', 0) > 5:
                health['status'] = 'degraded'
            if algo_health.get('status') == 'unhealthy':
                health['status'] = 'unhealthy'

        if screening_client:
            screening_health = screening_client.check_health()
            health['details']['screening'] = screening_health
            if screening_health.get('status') != 'healthy' and health['status'] == 'healthy':
                health['status'] = 'degraded'

        return JSONResponse(content=health, status_code=200)

    except Exception as e:
        logger.error(f"Health check failed: {e}", exc_info=True)
        return JSONResponse(content={"status": "unhealthy", "error": str(e)}, status_code=500)


class HealthServer:
    def __init__(self, host: str, port: int, trust_algo, nether_client, screening):
        global trust_algorithm, nethermind_client, screening_client
        trust_algorithm = trust_algo
        nethermind_client = nether_client
        screening_client = screening

        self._host = host
        self._port = port
        self._thread = threading.Thread(
            target=uvicorn.run,
            kwargs={
                "app": app,
                "host": self._host,
                "port": self._port,
                "log_level": "info"
            },
            daemon=True
        )

    def start(self):
        self._thread.start()

    def stop(self):
        # No reliable way to programmatically stop uvicorn.run. Process exit handles this.
        pass
