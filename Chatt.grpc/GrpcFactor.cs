using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.grpc
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
