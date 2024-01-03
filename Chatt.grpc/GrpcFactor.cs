using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Test;

namespace Chatt.Grpc
{
    public interface IGrpcFactor { }

    public sealed class GrpcFactor : IGrpcFactor
    {
        private static GrpcFactor _instance = null;
        internal static int port = 0;
        private static GreetingService.GreetingServiceClient GreetingClient = null;
        private static readonly object padlock = new object();

        // Twoja zmienna globalna
        public Server Server { get; set; }
        public List<GreetingService.GreetingServiceClient> greetingServiceClient { get; private set; }
        public List<TestingService.TestingServiceClient> testingServiceClient { get; private set; }
        private GrpcFactor()
        {
            // Prywatny konstruktor, aby uniemożliwić bezpośrednie tworzenie instancji
            port = new Random().Next(50000, 50010);
            Server = GrpcInitiator.CreateGrpcServer(Port: port);
            Server.Start();
            Debug.WriteLine("The server is listening on the port: " + port);
            //TODO: nie będzie tu tworzony domyślny klient tylko nowa instancja listy
            greetingServiceClient = new List<GreetingService.GreetingServiceClient>
            {
                GrpcInitiator.GrpcClientInitiator<GreetingService.GreetingServiceClient>.CreateGrpcClient(Port: port)
            };
            testingServiceClient = new List<TestingService.TestingServiceClient>
            {
                GrpcInitiator.GrpcClientInitiator<TestingService.TestingServiceClient>.CreateGrpcClient(Port: 44444)
            };
        }

        public static GreetingService.GreetingServiceClient GetClient(string address, int port)
        {
            GreetingClient = GrpcInitiator.GrpcClientInitiator<GreetingService.GreetingServiceClient>.CreateGrpcClient(address: address, Port: port);
            return GreetingClient;
        }

        public static GrpcFactor Instance
        {
            get
            {
                if (_instance == null)
                    lock (padlock)
                        if (_instance == null)
                            _instance = new GrpcFactor();
                return _instance;
            }
        }
    }
}
