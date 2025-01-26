curl 'https://rpc.aboutcircles.com/' \
 -H 'Content-Type: application/json' \
 --data-raw '{
   "jsonrpc": "2.0",
   "id": 0,
   "method": "circlesV2_findPath",
   "params": [
     {
       "Source": "0x0e50fc4e7d629bc5edd69b6dddb3c22c6e60704b",
       "Sink": "0xdca9d42a96ecf8ede1e6920bec08870bba69600e",
       "TargetFlow": "99999999999999999999999999999999999"
     }
   ]
 }'
