using Chatt.Entities.Model;
using Microsoft.EntityFrameworkCore;
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
        public DbSet<ConversationMessageModel> ConversationMessages { get; set; }

        string DbPath { get; set; }
        public ChattContext()
        {
            var folder = Environment.SpecialFolder.LocalApplicationData;
            var path = Environment.GetFolderPath(folder);
            DbPath = Path.Join(path, "chatt.db");
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            optionsBuilder.UseSqlite($"Data Source={DbPath}");
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<UserModel>().ToTable("Users");
            modelBuilder.Entity<ConversationModel>().ToTable("Conversations");
            modelBuilder.Entity<ConversationMessageModel>().ToTable("ConversationMessages");
        }
    }
}
