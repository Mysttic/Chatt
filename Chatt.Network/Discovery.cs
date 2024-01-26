using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Threading.Channels;

namespace Chatt.Network
{
    public static class Discovery
    {
        public static async IAsyncEnumerable<(string address,int port)> Discover(string[] addresses, int[] ports)
        {
            //var channel = Channel.CreateUnbounded<string>();
            foreach (string address in addresses)
            {
                if (await IsHostAvailableAsync(address, 1000))
                {
                    Debug.WriteLine($"Adres {address} istnieje");
                    foreach (int port in ports)
                    {
                        if (await IsIpPortListeningAsync(address, port))
                        {
                            Debug.WriteLine($"Nasłuchuje na {address}:{port}");
                            yield return (address, port);
                            //await channel.Writer.WriteAsync($"{address}:{port}");
                        }
                        else
                        {
                            Debug.WriteLine($"Adres {address} istnieje, ale nie nasłuchuje na porcie {port}");
                        }
                    }
                }
                else
                {
                    Debug.WriteLine($"Adres {address} nie istnieje");
                }
            }

        }

        public static async Task<bool> IsHostAvailableAsync(string ipAddress, int timeout)
        {
            try
            {
                using (Ping ping = new Ping())
                {
                    PingReply reply = await ping.SendPingAsync(ipAddress, timeout);
                    return reply.Status == IPStatus.Success;
                }
            }
            catch (PingException)
            {
                return false;
            }
        }
        public static async Task<bool> IsIpListeningAsync(string ipAddress)
        {
            try
            {
                using (TcpClient tcpClient = new TcpClient())
                {
                    var connectTask = tcpClient.ConnectAsync(ipAddress, 0); // Port 0 oznacza dowolny dostępny port
                    await Task.WhenAny(connectTask, Task.Delay(5000)); // Oczekiwanie maksymalnie 5 sekund

                    return tcpClient.Connected;
                }
            }
            catch (SocketException)
            {
                return false;
            }
        }
        public static async Task<bool> IsIpPortListeningAsync(string ipAddress, int port)
        {
            try
            {
                using (TcpClient tcpClient = new TcpClient())
                {
                    var connectTask = tcpClient.ConnectAsync(ipAddress, port);
                    await Task.WhenAny(connectTask, Task.Delay(5000)); // Oczekiwanie maksymalnie 5 sekund

                    return tcpClient.Connected;
                }
            }
            catch (SocketException)
            {
                return false;
            }
        }
    }
}