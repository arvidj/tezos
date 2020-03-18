#!/usr/bin/env python3
import time
import argparse
import os.path
from tools import constants, paths, utils
from launchers.sandbox import Sandbox


NODE_PARAMS = ['--connections', '3']


def scenario(contract, storage, time_between_blocks, proto):
    if proto is None:
        proto = 'alpha'
    assert proto in {'alpha', 'babylon'}, 'unknown protocol'
    protos = {'alpha': (constants.ALPHA, constants.ALPHA_DAEMON),
              'babylon': (constants.BABYLON, constants.BABYLON_DAEMON)}
    proto_hash, proto_daemon = protos[proto]
    if contract:
        assert os.path.isfile(contract), f'{contract} is not a file'
    if storage is None:
        storage = 'unit'
    with Sandbox(paths.TEZOS_HOME,
                 constants.IDENTITIES,
                 constants.GENESIS_PK) as sandbox:
        parameters = dict(constants.PARAMETERS)
        parameters["time_between_blocks"] = [str(time_between_blocks), "0"]

        sandbox.add_node(1, params=NODE_PARAMS)
        utils.activate_alpha(sandbox.client(1), parameters, proto=proto_hash)
        sandbox.add_baker(1, 'bootstrap5', proto=proto_daemon)
        client = sandbox.client(1)
        if contract:
            args = ['--init', storage, '--burn-cap', '10.0']
            sender = 'bootstrap2'
            amount = 0
            client.originate('my_contract', sender, amount, sender,
                             contract, args)
        while 1:
            client.get_head()
            time.sleep(time_between_blocks)


DESCRIPTION = '''
Utility script to run node/baker in sandbox mode (RPC port 18731).

The script launches client commands to import the bootstrap keys, it optionally
originates a contract on behalf of bootstrap2. Then it displays the chain head
every time_between_blocks seconds.
'''


def main():
    description = DESCRIPTION
    parser = argparse.ArgumentParser(description=description)

    parser.add_argument('--time-between-blocks', dest='time_between_blocks',
                        metavar='TIME',
                        help='time between blocks (seconds), default=2',
                        required=False, default='2')
    parser.add_argument('--contract', dest='contract', metavar='CONTRACT',
                        help='path to the contract', required=False)
    parser.add_argument('--storage', dest='storage', metavar='STORAGE',
                        help='initial storage for contract',
                        required=False
                        )
    parser.add_argument('--proto', dest='proto', metavar='PROTO',
                        help='alpha, babylon (default alpha)',
                        required=False
                        )
    args = parser.parse_args()
    scenario(args.contract, args.storage, int(args.time_between_blocks),
             args.proto)


if __name__ == "__main__":
    main()
