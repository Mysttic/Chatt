using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.Grpc
{
    public interface IGrpcFactor { }

    public class GrpcFactor : IGrpcFactor
    {
        private static GrpcFactor _instance;

        // Twoja zmienna globalna
        public Server Server { get; set; }
        public List<GreetingService.GreetingServiceClient> greetingServiceClient { get; private set; }

        private GrpcFactor()
        {
            // Prywatny konstruktor, aby uniemożliwić bezpośrednie tworzenie instancji

            Server = GrpcInitiator.CreateGrpcServer(Port: 50051);
            Server.Start();
            Console.WriteLine("The server is listening on the port: " + 50051);
            //TODO: nie będzie tu tworzony domyślny klient tylko nowa instancja listy
            greetingServiceClient = new List<GreetingService.GreetingServiceClient>
            {
                GrpcInitiator.CreateGrpcClient(Port: 50051)
            };
        }

        public static GrpcFactor Instance
        {
            get
            {
                if (_instance == null)
                {
                    _instance = new GrpcFactor();
                }
                return _instance;
            }
        }
    }
}
