using Greet;
using Grpc.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Test;

namespace Chatt.Grpc
{
    internal static class GrpcInitiator
    {
        internal static class GrpcClientInitiator<T> where T : ClientBase<T>
        {
            internal static T CreateGrpcClient(string address = "127.0.0.1", int Port = 0)
            {
                string target = $"{address}:{Port}";

                Channel channel = new Channel(target, ChannelCredentials.Insecure);

                channel.ConnectAsync().ContinueWith((task) =>
                {
                    if (task.Status == TaskStatus.RanToCompletion)
                    {
                        Console.WriteLine($"The client {target} connected successfully");
                    }
                });

                T greetingClient = (T)Activator.CreateInstance(typeof(T), channel);

                return greetingClient;
            }
        }

        //internal static GreetingService.GreetingServiceClient CreateGrpcClient(string address = "127.0.0.1", int Port = 0)
        //{
        //    string target = $"{address}:{Port}";

        //    Channel channel = new Channel(target, ChannelCredentials.Insecure);

        //    channel.ConnectAsync().ContinueWith((task) =>
        //    {
        //        if (task.Status == TaskStatus.RanToCompletion)
        //        {
        //            Console.WriteLine($"The client {target} connected successfully");
        //        }
        //    });

        //    var greetingClient = new GreetingService.GreetingServiceClient(channel);

        //    return greetingClient;
        //}

        internal static Server CreateGrpcServer(string address = "127.0.0.1", int Port = 0)
        {
            Server server = new Server()
            {
                Services =
                {
                    GreetingService.BindService(new GreetingServiceImpl()),
                    TestingService.BindService(new TestingServiceImpl())
                },
                Ports = { new ServerPort(address, Port, ServerCredentials.Insecure) }
            };
            return server;
        }
    }
}
