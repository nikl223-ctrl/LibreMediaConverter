import argparse
import unittest

from render_nft import TCP_PORTS, UDP_PORTS, interface_name, ipv4_address, ipv4_network, render_nft

class GatewayConfigTests(unittest.TestCase):
    def test_ports_and_guard(self):
        self.assertEqual(TCP_PORTS, (47984, 47989, 48010))
        self.assertEqual(UDP_PORTS, (47998, 47999, 48000, 48002, 48010))
        rules = render_nft('eth0', 'wg0', '10.77.0.2', '10.66.0.0/24')
        self.assertNotIn('47990', rules.split('table ip sunshine_gateway', 1)[1])
        self.assertIn('iifname "eth0" ip saddr 10.66.0.0/24', rules)
        self.assertIn('oifname "wg0" ip daddr 10.77.0.2', rules)
        self.assertIn('masquerade', rules)
        self.assertIn('dnat to 10.77.0.2', rules)

    def test_reject_bad_interface_names(self):
        for name in ('eth0;flush', 'wg 0', 'a' * 16, '', 'x"'):
            with self.subTest(name=name):
                with self.assertRaises(argparse.ArgumentTypeError):
                    interface_name(name)

    def test_validate_ips(self):
        for address in ('::1', '127.0.0.1', '0.0.0.0', '224.0.0.1', '169.254.1.1'):
            with self.subTest(address=address):
                with self.assertRaises(argparse.ArgumentTypeError):
                    ipv4_address(address)
        self.assertEqual(ipv4_network('10.66.0.3/24'), '10.66.0.0/24')

    def test_distinct_interfaces(self):
        with self.assertRaises(ValueError):
            render_nft('wg0', 'wg0', '10.77.0.2', '10.66.0.0/24')

if __name__ == '__main__':
    unittest.main()
