using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using static Greet.GreetingService;

namespace Chatt.Grpc
{
    public class GreetingServiceImpl : GreetingServiceBase
    {
        public override Task<GreetingResponse> Greet(GreetingRequest request, ServerCallContext context)
        {
            string result = String.Format("hello {0}\n{1}", request.Greeting.Nickname, request.Greeting.WelcomeMessage);
            Console.WriteLine("{0} ({1}) just called for server.", request.Greeting.Nickname, request.Greeting.Address);
            return Task.FromResult(new GreetingResponse() { Result = result });
        }
    }
}
