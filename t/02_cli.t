use strict;
use warnings;
use Test::More;
use Path::Class;
use lib file(__FILE__)->dir->file('lib')->stringify;

use base qw(Test::Class);

use Test::Cinnamon::CLI;

use constant { CLI_SUCCESS => 0, CLI_ERROR => 1 };

sub setup : Test(setup) {
    Cinnamon::Config::reset;
}

sub _help : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    is $app->run('--help'), CLI_SUCCESS;
    is $app->system_error, "Usage: cinnamon [--config=<path>] [--help] [--info] <role> <task ...>\n";
}

sub _info : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
role production  => sub { 'example.com'  }, { foo => 'bar' };
task update      => sub { 'do something' };
CONFIG
    is $app->run('--config=config/deploy.pl', '--info'), CLI_SUCCESS;
    is $app->system_output, <<"OUTPUT";
\e[37m---
roles:
  production:
    hosts: example.com
    params:
      foo: bar
tasks:
  update: !!perl/code '{ "DUMMY" }'
\e[0m
OUTPUT
}

sub _no_config : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    is $app->run('role', 'task'), CLI_ERROR;
    is $app->system_error, "cannot find config file for deploy : config/deploy.pl\nUsage: cinnamon [--config=<path>] [--help] [--info] <role> <task ...>\n";
}

sub _valid : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
set user => 'app';
role test => 'localhost';
task echo_user => sub {
    print(get 'user');
};
CONFIG
    is $app->run('test', 'echo_user'), CLI_SUCCESS;
    like $app->system_output, qr{app};
}

sub _change_config_name : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy_changed.pl", <<CONFIG);
use Cinnamon::DSL;
set user => 'app';
role test => 'localhost';
task echo_user => sub {
    print(get 'user');
};
CONFIG
    is $app->run('--config=config/deploy_changed.pl', 'test', 'echo_user'), CLI_SUCCESS;
    like $app->system_output, qr{app};
}

sub _read_command_line_args : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<'CONFIG');
use Cinnamon::DSL;
role test => 'localhost';
task args => sub {
    my $host  = shift;
    printf "%s\t%s\n", get('args1'), get('args2');
};
CONFIG
    is $app->run('test', 'args', '-s', 'args1=foo', '-s', 'args2=bar'), CLI_SUCCESS;
    like $app->system_output, qr{foo\tbar};
}

sub _more_tasks : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
set user       => 'app';
set deploy_to  => '/home/app/deploy_to';
role test => 'localhost';
task echo_user => sub {
    print(get 'user');
};
task echo_deploy_to => sub {
    print(get 'deploy_to');
};
CONFIG
    is $app->run('test', 'echo_user', 'echo_deploy_to'), CLI_SUCCESS;
    like $app->system_output, qr{app};
    like $app->system_output, qr{deploy_to};
}

sub _fail_at_more_tasks : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
set user       => 'app';
set deploy_to  => '/home/app/deploy_to';
role test => 'localhost';
task die_user => sub {
    die get 'user';
};
task echo_deploy_to => sub {
    print(get 'deploy_to');
};
CONFIG
    is $app->run('test', 'die_user', 'echo_deploy_to'), CLI_ERROR;
    like $app->system_error, qr{app};
    unlike $app->system_output, qr{deploy_to};

    # specified undefined task
    is $app->run('test', 'undef_task', 'echo_deploy_to'), CLI_ERROR;
    like $app->system_error, qr{undefined task : 'undef_task'};
    unlike $app->system_output, qr{deploy_to};
}

sub _fail_at_more_tasks_with_ignore_errors_option : Tests {
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
set user       => 'app';
set deploy_to  => '/home/app/deploy_to';
role test => 'localhost';
task die_user => sub {
    die get 'user';
};
task echo_deploy_to => sub {
    print(get 'deploy_to');
};
CONFIG
    is $app->run('--ignore-errors', 'test', 'die_user', 'echo_deploy_to'), CLI_ERROR;
    like $app->system_error, qr{app};
    like $app->system_output, qr{deploy_to};

    # specified undefined task
    is $app->run('--ignore-errors', 'test', 'undef_task', 'die_user', 'echo_deploy_to'), CLI_ERROR;
    like $app->system_error, qr{undefined task : 'undef_task'};
    like $app->system_error, qr{app};
    like $app->system_output, qr{deploy_to};
}

sub _specifies_colorized_output : Tests {
    require Term::ANSIColor;
    my $app = Test::Cinnamon::CLI::cli();
    $app->dir->touch("config/deploy.pl", <<CONFIG);
use Cinnamon::DSL;
role colorful   => 'localhost';
task echo_color => sub { printf 'color me surprised' };
CONFIG

    my $output = '[error]: ';
    my $color  = Term::ANSIColor::colored($output, 'red');
    is $app->run('colorful', 'echo_color'), CLI_SUCCESS;
    is $app->system_error, $color . "\n";

    is $app->run('--no-color', 'colorful', 'echo_color'), CLI_SUCCESS;
    is $app->system_error, $output . "\n";
}

__PACKAGE__->runtests;
