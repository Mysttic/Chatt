using Chatt.Server;
using Greet;
using Grpc.Core;
using Grpc.Reflection;
using Grpc.Reflection.V1Alpha;

const int Port = 50051;

Server? server = null;

try
{
    var reflectionServiceImpt = new ReflectionServiceImpl(GreetingService.Descriptor, ServerReflection.Descriptor);
        
    server.Start();
    Console.WriteLine($"Server listening on port: {Port}");
    Console.ReadKey();
}
catch (IOException e)
{
    Console.WriteLine($"Server failed to start: {e.Message}");
    throw;
}
finally
{
    if (server != null)
        server.ShutdownAsync().Wait();
}