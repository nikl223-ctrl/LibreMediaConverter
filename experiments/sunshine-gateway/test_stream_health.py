import unittest

from stream_health import cpu_sample, cpu_percentage, network_sample, diff_counters, percentile, parse_ping_ms

class StreamHealthTests(unittest.TestCase):
    def test_cpu_usage(self):
        self.assertEqual(cpu_sample("cpu  100 0 10 60 10 0 0 0\ncpu0 100\n"), (180, 70))
        self.assertEqual(cpu_percentage((100, 20), (200, 70)), 50.0)
        self.assertEqual(cpu_percentage((100, 20), (100, 20)), 0.0)

    def test_interface_counters(self):
        contents = (
            "Inter-|   Receive                                                |  Transmit\n"
            " face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n"
            "  wg0: 1000 5 1 2 0 0 0 0 2000 10 3 4 0 0 0 0\n"
            "  eth0: 300 1 0 0 0 0 0 0 500 2 0 0 0 0 0 0\n"
        )
        self.assertEqual(network_sample(contents, "wg0"), {
            "rx_bytes": 1000, "rx_errs": 1, "rx_drops": 2,
            "tx_bytes": 2000, "tx_errs": 3, "tx_drops": 4,
        })
        self.assertEqual(network_sample(contents, "eth0")["rx_bytes"], 300)
        with self.assertRaises(ValueError):
            network_sample(contents, "wlan0")

    def test_diff_counters(self):
        self.assertEqual(diff_counters({"a": 10, "b": 5}, {"a": 15, "b": 2}), {"a": 5, "b": 0})

    def test_network_latency_metrics(self):
        self.assertEqual(parse_ping_ms("64 bytes: icmp_seq=1 ttl=64 time=0.32 ms"), 0.32)
        self.assertEqual(parse_ping_ms("request timeout"), None)
        self.assertEqual(percentile([4, 2, 9, 5, 7], .95), 9)
        self.assertEqual(percentile([], .95), None)

if __name__ == "__main__":
    unittest.main()
