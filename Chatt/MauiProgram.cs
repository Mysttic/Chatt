using Chatt.Entities;
using Chatt.Entities.Model;
using Chatt.Grpc;
using Greet;
using Grpc.Core;
using Microsoft.Extensions.Logging;

namespace Chatt;

public static class MauiProgram
{

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

        builder.Services.AddSingleton<IGrpcFactor>(GrpcFactor.Instance);

		builder.Services.AddSingleton<BaseRepository<UserModel>>();
		builder.Services.AddSingleton<BaseRepository<SettingsModel>>();
		builder.Services.AddSingleton<BaseRepository<MessageModel>>();
		builder.Services.AddSingleton<BaseRepository<ConversationModel>>();

#if DEBUG
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}


    
}
