from dataclasses import dataclass
import aiohttp
from typing import List

@dataclass
class TransferPathStep:
    from_addr: str
    to: str
    token_owner: str
    value: str

@dataclass
class FlowEdge:
    stream_sink_id: int
    amount: int

@dataclass
class Stream:
    source_coordinate: int
    flow_edge_ids: List[int]
    data: bytes

@dataclass
class FlowMatrix:
    flow_vertices: List[str]
    flow_edges: List[FlowEdge]
    streams: List[Stream]
    packed_coordinates: bytes
    source_coordinate: int

@dataclass
class MaxFlowResponse:
    max_flow: str
    transfers: List[TransferPathStep]

class V2Pathfinder:
    def __init__(self, circles_rpc_url: str):
        self.circles_rpc_url = circles_rpc_url

    async def get_max_flow(self, from_addr: str, to: str) -> int:
        request_body = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "circlesV2_findPath",
            "params": [{
                "Source": from_addr,
                "Sink": to,
                "TargetFlow": "99999999999999999999999999999999999"
            }]
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(self.circles_rpc_url, json=request_body) as response:
                result = await response.json()
                return int(result['result']['maxFlow'])

    async def get_path(self, from_addr: str, to: str, value: str) -> MaxFlowResponse:
        request_body = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "circlesV2_findPath",
            "params": [{
                "Source": from_addr,
                "Sink": to,
                "TargetFlow": str(value)
            }]
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(self.circles_rpc_url, json=request_body) as response:
                result = await response.json()
                return result['result']

    async def get_args_for_path(self, from_addr: str, to: str, value: str) -> FlowMatrix:
        request_body = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "circlesV2_findPath",
            "params": [{
                "Source": from_addr,
                "Sink": to,
                "TargetFlow": str(value)
            }]
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(self.circles_rpc_url, json=request_body) as response:
                result = await response.json()
                transfers = result['result']['transfers']

                if transfers:
                    transfer_steps = [
                        TransferPathStep(
                            from_addr=t['from'],
                            to=t['to'],
                            token_owner=t['tokenOwner'],
                            value=t['value']
                        ) for t in transfers
                    ]
                    return create_flow_matrix(from_addr, to, value, transfer_steps)
                else:
                    raise Exception("No transfers found in response from pathfinder")

def transform_to_flow_vertices(transfers: List[TransferPathStep], from_addr: str, to: str):
    address_set = set()
    address_set.add(from_addr.lower())
    address_set.add(to.lower())
    for transfer in transfers:
        address_set.add(transfer.from_addr.lower())
        address_set.add(transfer.to.lower())
        address_set.add(transfer.token_owner.lower())

    sorted_addresses = sorted(list(address_set), key=lambda x: int(x, 16))

    lookup_map = {addr: idx for idx, addr in enumerate(sorted_addresses)}

    return {
        "sorted_addresses": sorted_addresses,
        "lookup_map": lookup_map
    }

def pack_coordinates(coordinates: List[int]) -> bytes:
    packed = bytearray(len(coordinates) * 2)
    for i, coord in enumerate(coordinates):
        packed[2*i] = (coord >> 8) & 0xff
        packed[2*i + 1] = coord & 0xff
    return bytes(packed)

def create_flow_matrix(from_addr: str, to: str, value: str, transfers: List[TransferPathStep]) -> FlowMatrix:
    expected_value = int(value)

    result = transform_to_flow_vertices(transfers, from_addr.lower(), to.lower())
    sorted_addresses = result["sorted_addresses"]
    lookup_map = result["lookup_map"]

    flow_edges = [
        FlowEdge(
            stream_sink_id=1 if transfer.to.lower() == to.lower() else 0,
            amount=int(transfer.value)
        )
        for transfer in transfers
    ]

    if not any(edge.stream_sink_id == 1 for edge in flow_edges):
        last_index = [t.to.lower() for t in transfers].index(to.lower())
        if last_index != -1:
            flow_edges[last_index].stream_sink_id = 1
        else:
            flow_edges[-1].stream_sink_id = 1

    total_terminal_amount = sum(edge.amount for edge in flow_edges if edge.stream_sink_id == 1)

    if total_terminal_amount != expected_value:
        raise Exception(f"Total terminal amount ({total_terminal_amount}) does not match provided value ({expected_value})")

    flow_edge_ids = [i for i, edge in enumerate(flow_edges) if edge.stream_sink_id == 1]

    stream = Stream(
        source_coordinate=lookup_map[from_addr.lower()],
        flow_edge_ids=flow_edge_ids,
        data=b''
    )

    coordinates = []
    for transfer in transfers:
        coordinates.extend([
            lookup_map[transfer.token_owner.lower()],
            lookup_map[transfer.from_addr.lower()],
            lookup_map[transfer.to.lower()]
        ])
    packed_coordinates = pack_coordinates(coordinates)

    return FlowMatrix(
        flow_vertices=sorted_addresses,
        flow_edges=flow_edges,
        streams=[stream],
        packed_coordinates=packed_coordinates,
        source_coordinate=lookup_map[from_addr.lower()]
    )
