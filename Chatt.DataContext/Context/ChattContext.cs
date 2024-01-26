using Chatt.Entities.Model;
using Microsoft.EntityFrameworkCore;
using Microsoft.VisualBasic;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Chatt.DataContext.Context
{
    public class ChattContext : DbContext
    {
        public DbSet<UserModel> Users { get; set; }
        public DbSet<ConversationModel> Conversations { get; set; }
        public DbSet<MessageModel> ConversationMessages { get; set; }
        public DbSet<SettingsModel> Settings { get; set; }


        string DbPath { get; set; }
        public ChattContext()
        {
            var folder = Environment.SpecialFolder.LocalApplicationData;
            var path = Environment.GetFolderPath(folder);
            path = Path.Join(path, "Chatt");
            if (!Directory.Exists(path))            
                Directory.CreateDirectory(path);
            DbPath = Constants.DatabasePath;
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            optionsBuilder.UseSqlite($"Data Source={DbPath}");
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<UserModel>().ToTable("Users");
            modelBuilder.Entity<ConversationModel>().ToTable("Conversations");
            modelBuilder.Entity<MessageModel>().ToTable("ConversationMessages");
            modelBuilder.Entity<SettingsModel>().ToTable("Settings");

            modelBuilder.Entity<SettingsModel>().HasData(
            new SettingsModel
            {
                Id = 1, // Ustaw odpowiednie ID, jeśli jest wymagane
                Nickname = "Standardowy Nick",
                WelcomeMessage = "Witaj w naszej aplikacji!",
                ActivePort = 0,
                CustomPort = 50004, // Przykładowe wartości
                IpFilter = "",
                PortFilter = ""
            });
        }
    }
}
