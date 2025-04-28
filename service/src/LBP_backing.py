import asyncio
from clients.screening import ScreeningClient
from clients.lbp_indexer import CirclesBackingHandler
from config.settings import settings

async def main():
    # Initialize blacklist screening client with the endpoint URL
    screening_client = ScreeningClient(base_url=settings.screening_url)

    # Initialize the CirclesBackingHandler
    backing_handler = CirclesBackingHandler(
        rpc_url=settings.nethermind_rpc_url,
        screening_client=screening_client,
        baseGroup_address=settings.baseGroup_address,
        private_key=settings.private_key
    )

    # Run the event processor (this will block)
    backing_handler.run_event_processor(poll_interval=15)  # Default poll interval

if __name__ == "__main__":
    asyncio.run(main())
