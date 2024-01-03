using Chatt.Entities.Model;
using Chatt.Grpc;
using Chatt.Views;
using Greet;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Input;
using static Greet.GreetingService;

namespace Chatt.ViewModels
{
    public class ConversationViewModel
    {
        ConversationView ContentPage { get; set; }
        public ConversationModel ConversationModel { get; set; }
        SettingsModel SettingsModel { get; set; }
        public ObservableCollection<MessageModel> ConversationMessages { get; set; }
        public ConversationViewModel(ConversationView contentPage, ConversationModel conversationModel) 
        { 
            ContentPage = contentPage;
            ConversationModel = conversationModel;
            SettingsModel = new SettingsModel();
            Load();
            GreetWelcome(GrpcFactor.Instance.greetingServiceClient.FirstOrDefault());
        }

        public ICommand GoHome => new Command(async (object obj) =>
        {
            await ContentPage.Window.Navigation.PopModalAsync();
        });

        async Task Load()
        {
            var messages = App.MessagesRepo.GetItems();
            ConversationMessages = new ObservableCollection<MessageModel>(messages);
        }

        public void GreetWelcome(GreetingServiceClient client)
        {
            var greeting = new Greeting()
            {
                Nickname = ConversationModel?.User?.NickName,
            };

            var greetingRequest = new GreetingRequest() { Greeting = greeting };

            var greetingResponse = client.Greet(greetingRequest);

            Console.WriteLine(greetingResponse.Result);

            App.MessagesRepo.SaveItem(new MessageModel() { Message = greetingResponse.Result });
            Load();
            //ConversationMessages.Add();
        }
    }
}
