using Chatt.grpc;
using Greet;
using Grpc.Core;
using Microsoft.Extensions.Logging;

namespace Chatt;

public static class MauiProgram
{
    public static Server Server { get; private set; }
    public static List<GreetingService.GreetingServiceClient> greetingServiceClient { get; private set; }

    static int Port;
    public static MauiApp CreateMauiApp()
	{
        var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.ConfigureFonts(fonts =>
			{
				fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
				fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
			});

        Port = new Random().Next(50050, 50060);
        Server = CreateGrpcServer();
        //greetingServiceClient = CreateGrpcClient();

#if DEBUG
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}

    

	public static Server CreateGrpcServer()
	{
        Server server = null;

        try
        {
            server = new Server()
            {
                Services = { GreetingService.BindService(new GreetingServiceImpl()) },
                Ports = { new ServerPort("localhost", Port, ServerCredentials.Insecure) }
            };
            server.Start();
            Console.WriteLine("The server is listening on the port: " + Port);
        }
        catch (IOException e)
        {
            Console.WriteLine("The server failed to start: " + e.Message);
            throw;
        }
        //finally
        //{
        //    //if (server != null)
        //    //{
        //    //    server.ShutdownAsync().Wait();
        //    //}
        //}

        return server;
    }

    public static GreetingService.GreetingServiceClient CreateGrpcClient(string address = "127.0.0.1", int Port = 0)
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

        var greetingClient = new GreetingService.GreetingServiceClient(channel);

        return greetingClient;
    }
}
