# Copyright (C) 2018-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::Test;
use Mojo::Base -base;

use Mojo::File qw(path tempdir);
use Mojo::Pg;
use Mojo::URL;
use Mojo::Util qw(scope_guard);

sub new {
  my ($class, %options) = @_;

  # Database
  my $self = $class->SUPER::new(options => \%options);
  $self->{pg}       = Mojo::Pg->new($options{online});
  $self->{db_guard} = $self->_prepare_schema($options{schema});

  # Temporary directories
  $self->{checkout_dir} = tempdir;
  $self->{cache_dir}    = tempdir;

  return $self;
}

sub cache_dir    { shift->{cache_dir} }
sub checkout_dir { shift->{checkout_dir} }

sub default_config {
  my $self = shift;
  return {
    secrets                => ['just_a_test'],
    checkout_dir           => $self->checkout_dir,
    cache_dir              => $self->cache_dir,
    tokens                 => ['test_token'],
    pg                     => $self->postgres_url,
    acceptable_risk        => 3,
    index_bucket_average   => 100,
    cleanup_bucket_average => 50,
    min_files_short_report => 20,
    max_email_url_size     => 26,
    max_task_memory        => 5_000_000_000,
    max_worker_rss         => 100000,
    max_expanded_files     => 100
  };
}

sub mojo_fixtures {
  my ($self, $app) = @_;
  $self->no_fixtures($app);

  # Create checkout directory
  my $dir       = $self->checkout_dir;
  my @src       = ('perl-Mojolicious', 'c7cfdab0e71b0bebfdf8b2dc3badfecd');
  my $mojo      = $dir->child(@src)->make_path;
  my $legal_bot = path(__FILE__)->dirname->dirname->dirname->child('legal-bot');
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;
  @src  = ('perl-Mojolicious', 'da3e32a3cce8bada03c6a9d63c08cd58');
  $mojo = $dir->child(@src)->make_path;
  $_->copy_to($mojo->child($_->basename)) for $legal_bot->child(@src)->list->each;

  # Create fixtures
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'c7cfdab0e71b0bebfdf8b2dc3badfecd',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'bd91c36647a5d3dd883d490da2140401',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $pkg2_id = $pkgs->add(
    name            => 'perl-Mojolicious',
    checkout_dir    => 'da3e32a3cce8bada03c6a9d63c08cd58',
    api_url         => 'https://api.opensuse.org',
    requesting_user => 1,
    project         => 'devel:languages:perl',
    package         => 'perl-Mojolicious',
    srcmd5          => 'da3e32a3cce8bada03c6a9d63c08cd58',
    priority        => 5
  );
  $pkgs->imported($pkg2_id);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'You may obtain a copy of the License at', license => 'Apache-2.0');
  $patterns->create(
    packname => 'perl-Mojolicious',
    pattern  => 'Licensed under the Apache License, Version 2.0',
    license  => 'Apache-2.0'
  );
  $patterns->create(pattern => 'License: Artistic-2.0',            license => 'Artistic-2.0');
  $patterns->create(pattern => 'powerful web development toolkit', license => 'SUSE-NotALicense');
  $patterns->create(pattern => 'the terms');
  $patterns->create(pattern => 'copyright notice');
}

sub no_fixtures {
  my ($self, $app) = @_;

  $app->pg->migrations->migrate;

  # Allow Devel::Cover to collect stats for background jobs
  $app->minion->on(
    worker => sub {
      my ($minion, $worker) = @_;
      $worker->on(
        dequeue => sub {
          my ($worker, $job) = @_;
          $job->on(cleanup => sub { Devel::Cover::report() if Devel::Cover->can('report') });
        }
      );
    }
  );
}

sub package_with_snippets_fixtures {
  my ($self, $app) = @_;
  $self->no_fixtures($app);

  # Create checkout directory
  my $dir = $self->checkout_dir;
  my @src = ('package-with-snippets', '2a0737e27a3b75590e7fab112b06a76fe7573615');
  my $src = $dir->child(@src)->make_path;
  $_->copy_to($src->child($_->basename))
    for path(__FILE__)->dirname->dirname->dirname->child('legal-bot', @src)->list->each;

  # Create fixtures
  my $usr_id = $app->pg->db->insert('bot_users', {login => 'test_bot'}, {returning => 'id'})->hash->{id};
  my $pkgs   = $app->packages;
  my $pkg_id = $pkgs->add(
    name            => 'package-with-snippets',
    checkout_dir    => '2a0737e27a3b75590e7fab112b06a76fe7573615',
    api_url         => 'https://api.opensuse.org',
    requesting_user => $usr_id,
    project         => 'devel:languages:perl',
    package         => 'package-with-snippets',
    srcmd5          => '2a0737e27a3b75590e7fab112b06a76fe7573615',
    priority        => 5
  );
  $pkgs->imported($pkg_id);
  my $patterns = $app->patterns;
  $patterns->create(pattern => 'license');
  $patterns->create(pattern => 'GPL', license => 'GPL');
  $patterns->create(
    pattern => 'Permission is granted to copy, distribute and/or modify this document
       under the terms of the GNU Free Documentation License, Version 1.1 or any later
       version published by the Free Software Foundation; with no Invariant Sections,
       with no Front-Cover Texts and with no Back-Cover Texts. A copy of the license
       is included in the section entitled "GNU Free Documentation License"',
    license => 'GFDL-1.1-or-later'
  );
}

sub postgres_url {
  my $self = shift;
  return Mojo::URL->new($self->{options}{online})->query([search_path => [$self->{options}{schema}, 'public']])
    ->to_unsafe_string;
}

sub _prepare_schema {
  my ($self, $name) = @_;

  # Isolate tests
  my $pg = $self->{pg};
  $pg->db->query("drop schema if exists $name cascade");
  $pg->db->query("create schema $name");

  # Clean up once we are done
  return scope_guard sub { $pg->db->query("drop schema $name cascade") };
}

1;
