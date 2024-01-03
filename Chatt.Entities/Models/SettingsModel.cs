using PropertyChanged;
using SQLite;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Entities.Model
{
    [AddINotifyPropertyChangedInterface]
    [Table("Settings")]
    public class SettingsModel : TableData
    {
        [Indexed, NotNull, MaxLength(255)]
        public string Nickname { get; set; } = string.Empty;
        [NotNull, MaxLength(255)]
        public string WelcomeMessage { get; set; } = string.Empty;

        /// <summary>
        /// This field determine on which port app is listening actualy
        /// It can be any value from all values defined in CustomPort field
        /// </summary>
        [MaxLength(255)] 
        public string ActivePort { get; set; } = string.Empty;
        [MaxLength(255)]
        public string CustomPort { get; set; } = string.Empty;
        [MaxLength(255)]
        public string IpFilter { get; set; } = string.Empty;
        [MaxLength(255)]
        public string PortFilter { get; set; } = string.Empty;

        public List<string> ExtractIPAddresses()
        {
            List<string> result = new List<string>();

            string[] addressGroups = IpFilter.Split(';');
            foreach (string addressGroup in addressGroups)
            {
                string trimmedAddressGroup = addressGroup.Trim();
                if (trimmedAddressGroup.Contains("-"))
                {
                    // Przetwarzanie zakresu adresów IP
                    string[] range = trimmedAddressGroup.Split('-');
                    if (range.Length == 2 && IPAddress.TryParse(range[0], out IPAddress? startIp) && IPAddress.TryParse(range[1], out IPAddress? endIp))
                    {
                        while (!startIp.Equals(endIp))
                        {
                            result.Add(startIp.ToString());
                            byte[] bytes = startIp.GetAddressBytes();
                            for (int i = bytes.Length - 1; i >= 0; i--)
                            {
                                if (bytes[i] == byte.MaxValue)
                                {
                                    bytes[i] = 0;
                                }
                                else
                                {
                                    bytes[i]++;
                                    break;
                                }
                            }
                            startIp = new IPAddress(bytes);
                        }
                        result.Add(endIp.ToString());
                    }
                }
                else if (trimmedAddressGroup.Contains("*"))
                {
                    // Przetwarzanie wildcard (*) dla ostatniego oktetu
                    string[] parts = trimmedAddressGroup.Split('.');
                    if (parts.Length == 4)
                    {
                        for (int i = 0; i <= 255; i++)
                        {
                            parts[3] = i.ToString();
                            result.Add(string.Join(".", parts));
                        }
                    }
                }
                else
                {
                    // Dodawanie pojedynczego adresu IP
                    result.Add(trimmedAddressGroup);
                }
            }
            return result;
        }

        public List<int> ExtractPorts()
        {
            List<int> result = new List<int>();

            string[] portGroups = PortFilter.Split(';');
            foreach (string portGroup in portGroups)
            {
                string trimmedPortGroup = portGroup.Trim();
                if (trimmedPortGroup.Contains("-"))
                {
                    // Przetwarzanie zakresu portów
                    string[] range = trimmedPortGroup.Split('-');
                    if (range.Length == 2 && int.TryParse(range[0], out int startPort) && int.TryParse(range[1], out int endPort))
                    {
                        for (int currentPort = startPort; currentPort <= endPort; currentPort++)
                        {
                            result.Add(currentPort);
                        }
                    }
                }
                else
                {
                    // Dodawanie pojedynczego portu
                    if (int.TryParse(trimmedPortGroup, out int singlePort))
                    {
                        result.Add(singlePort);
                    }
                }
            }
            return result;
        }

        public string GetIPAddress()
        {
            return Dns.GetHostEntry(Dns.GetHostName()).AddressList.FirstOrDefault(x=>x.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)?.ToString() ?? "";
        }
    }
}
