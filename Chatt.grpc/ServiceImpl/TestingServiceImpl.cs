using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Test;
using static Test.TestingService;

namespace Chatt.Grpc
{
    public class TestingServiceImpl : TestingServiceBase
    {
        public override Task<TestingResponse> Test(TestingRequest request, ServerCallContext context)
        {
            string result = String.Format("{0}", request.Testing.TestMessage);
            Console.WriteLine("{0} ", request.Testing.TestMessage);
            return Task.FromResult(new TestingResponse() { Result = result });
        }
    }
}
