using Chatt.Entities.Model;
using Chatt.Grpc;
using Chatt.Network;
using Chatt.UI;
using Chatt.Views;
using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;
using static Chatt.Network.Discovery;
using static Greet.GreetingService;

namespace Chatt.ViewModels
{
    public class UsersNearbyViewModel
    {
        UsersNearbyView ContentPage { get; set; }
        public SettingsModel SettingsModel { get; set; }

        public ObservableCollection<UserModel> Users { get; set; }

        public UsersNearbyViewModel(UsersNearbyView contentPage)
        {
            ContentPage = contentPage;
            Load();
        }

        public ICommand GoHome => new Command(async (object obj) =>         
        { 
            await ContentPage.Window.Navigation.PopModalAsync(); 
        });

        public ICommand SearchPeople => new Command(async () =>
        {
            string[] IpAddresses = SettingsModel.ExtractIPAddresses().ToArray();
            int[] Ports = SettingsModel.ExtractPorts().ToArray();
            var list = new List<string>();
            await foreach(var item in Discover(IpAddresses, Ports))
            {
                list.Add($"{item.address}:{item.port}");
                var greeting = new Greeting()
                {
                    Nickname = SettingsModel.Nickname,
                    WelcomeMessage = SettingsModel.WelcomeMessage,
                    Address = $"{SettingsModel.GetIPAddress()}:{SettingsModel.ActivePort}"
                };

                GreetingServiceClient client = GrpcFactor.GetClient(item.address, item.port);

                var greetingRequest = new GreetingRequest() { Greeting = greeting };

                try
                {
                    var greetingResponse = await client.GreetAsync(greetingRequest);

                    Debug.WriteLine(greetingResponse.Result);
                }
                catch (RpcException ex) { }
            }
            Debug.WriteLine(list.Count);
                //foreach (int port in Ports)
                //{
                //string address = "127.0.0.1";
                //if (await IsListeningAsync(address, port))
                //{
                //    Debug.WriteLine($"Nasłuchuje na {address}:{port} ");
                //}
                //else
                //{
                //    Debug.WriteLine($"adres {address}:{port} jest głuchy");
                //}
                //var greeting = new Greeting()
                //{
                //    Nickname = SettingsModel.Nickname,
                //    WelcomeMessage = SettingsModel.WelcomeMessage,
                //    Address = $"{SettingsModel.GetIPAddress()}:{SettingsModel.ActivePort}"
                //};

                //GreetingServiceClient client = GrpcFactor.GetClient(address, port);

                //var greetingRequest = new GreetingRequest() { Greeting = greeting };

                //try
                //{
                //    var greetingResponse = await client.GreetAsync(greetingRequest);

                //    Console.WriteLine(greetingResponse.Result);
                //}
                //catch (RpcException ex) { }
            
        });

        

        async Task Load()
        {
            SettingsModel = new SettingsModel()
            {
                Nickname = "Dante devilry",
                WelcomeMessage = "Your welcome message",
                CustomPort = "50001-50010;50050;50075",
                ActivePort = "50001",
                IpFilter = "192.168.0.1-192.168.0.255;192.168.10.10;192.168.10.*",
                PortFilter = "50001-50010;50050;50075"
            };
            Users = new ObservableCollection<UserModel>()
            {
                //new UserModel()
                //{
                //    NickName = "Dyzio",
                //    IpAddress = "127.0.0.1",
                //    WelcomeMessage = "Hello there!"
                //},
                //new UserModel()
                //{
                //    NickName = "Hyzio",
                //    IpAddress = "192.168.0.1",
                //    WelcomeMessage = "Hi, im Hyzio please text me."

                //},
                //new UserModel()
                //{
                //    NickName = "Zyzio",
                //    IpAddress = "1.1.0.1",
                //    WelcomeMessage = ""
                //}
            };
        }
    }
}
