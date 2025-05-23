// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { console2 as console } from "forge-std/console2.sol";

import { Deployer } from "./Deployer.sol";
import { PeripheryDeployConfig } from "./PeripheryDeployConfig.s.sol";

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { Proxy } from "src/universal/Proxy.sol";

import { Faucet } from "src/periphery/faucet/Faucet.sol";
import { Drippie } from "src/periphery/drippie/Drippie.sol";
import { CheckGelatoLow } from "src/periphery/drippie/dripchecks/CheckGelatoLow.sol";
import { CheckBalanceHigh } from "src/periphery/drippie/dripchecks/CheckBalanceHigh.sol";
import { CheckBalanceLow } from "src/periphery/drippie/dripchecks/CheckBalanceLow.sol";
import { CheckTrue } from "src/periphery/drippie/dripchecks/CheckTrue.sol";
import { AdminFaucetAuthModule } from "src/periphery/faucet/authmodules/AdminFaucetAuthModule.sol";

/// @title DeployPeriphery
/// @notice Script used to deploy periphery contracts.
contract DeployPeriphery is Deployer {
    PeripheryDeployConfig cfg;

    /// @notice The name of the script, used to ensure the right deploy artifacts
    ///         are used.
    function name() public pure override returns (string memory) {
        return "DeployPeriphery";
    }

    function setUp() public override {
        super.setUp();

        string memory path = string.concat(vm.projectRoot(), "/periphery-deploy-config/", deploymentContext, ".json");
        cfg = new PeripheryDeployConfig(path);

        console.log("Deploying from %s", deployScript);
        console.log("Deployment context: %s", deploymentContext);
    }

    /// @notice Deploy all of the periphery contracts
    function run() public {
        console.log("Deploying all periphery contracts");

        deployProxies();
        deployImplementations();

        initializeFaucet();
        installFaucetAuthModulesConfigs();
    }

    /// @notice Deploy all of the proxies
    function deployProxies() public {
        deployProxyAdmin();

        deployFaucetProxy();
    }

    /// @notice Deploy all of the implementations
    function deployImplementations() public {
        deployFaucet();
        deployFaucetDrippie();
        deployCheckTrue();
        deployCheckBalanceLow();
        deployCheckBalanceHigh();
        deployCheckGelatoLow();
        deployOnChainAuthModule();
        deployOffChainAuthModule();
    }

    /// @notice Deploy the ProxyAdmin
    function deployProxyAdmin() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("ProxyAdmin"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(ProxyAdmin).creationCode, abi.encode(msg.sender)));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("ProxyAdmin already deployed at %s", preComputedAddress);
            save("ProxyAdmin", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            ProxyAdmin admin = new ProxyAdmin{ salt: salt }({ _owner: msg.sender });
            require(admin.owner() == msg.sender);

            save("ProxyAdmin", address(admin));
            console.log("ProxyAdmin deployed at %s", address(admin));

            addr_ = address(admin);
        }
    }

    /// @notice Deploy the FaucetProxy
    function deployFaucetProxy() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("FaucetProxy"));
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(Proxy).creationCode, abi.encode(proxyAdmin)));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("FaucetProxy already deployed at %s", preComputedAddress);
            save("FaucetProxy", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            Proxy proxy = new Proxy{ salt: salt }({ _admin: proxyAdmin });
            address admin = address(uint160(uint256(vm.load(address(proxy), OWNER_KEY))));
            require(admin == proxyAdmin);

            save("FaucetProxy", address(proxy));
            console.log("FaucetProxy deployed at %s", address(proxy));

            addr_ = address(proxy);
        }
    }

    /// @notice Deploy the faucet contract.
    function deployFaucet() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("Faucet"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(Faucet).creationCode, abi.encode(cfg.faucetAdmin())));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("Faucet already deployed at %s", preComputedAddress);
            save("Faucet", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            Faucet faucet = new Faucet{ salt: salt }(cfg.faucetAdmin());
            require(faucet.ADMIN() == cfg.faucetAdmin());

            save("Faucet", address(faucet));
            console.log("Faucet deployed at %s", address(faucet));

            addr_ = address(faucet);
        }
    }

    /// @notice Deploy drippie contract.
    function deployFaucetDrippie() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("FaucetDrippie"));
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(Drippie).creationCode, abi.encode(cfg.faucetDrippieOwner())));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("FaucetDrippie already deployed at %s", preComputedAddress);
            save("FaucetDrippie", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            Drippie drippie = new Drippie{ salt: salt }(cfg.faucetDrippieOwner());

            save("FaucetDrippie", address(drippie));
            console.log("FaucetDrippie deployed at %s", address(drippie));

            addr_ = address(drippie);
        }
    }

    /// @notice Deploy CheckTrue contract.
    function deployCheckTrue() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("CheckTrue"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CheckTrue).creationCode));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("CheckTrue already deployed at %s", preComputedAddress);
            save("CheckTrue", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            CheckTrue checkTrue = new CheckTrue{ salt: salt }();

            save("CheckTrue", address(checkTrue));
            console.log("CheckTrue deployed at %s", address(checkTrue));

            addr_ = address(checkTrue);
        }
    }

    /// @notice Deploy CheckBalanceLow contract.
    function deployCheckBalanceLow() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("CheckBalanceLow"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CheckBalanceLow).creationCode));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("CheckBalanceLow already deployed at %s", preComputedAddress);
            save("CheckBalanceLow", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            CheckBalanceLow checkBalanceLow = new CheckBalanceLow{ salt: salt }();

            save("CheckBalanceLow", address(checkBalanceLow));
            console.log("CheckBalanceLow deployed at %s", address(checkBalanceLow));

            addr_ = address(checkBalanceLow);
        }
    }

    /// @notice Deploy CheckBalanceHigh contract.
    function deployCheckBalanceHigh() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("CheckBalanceHigh"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CheckBalanceHigh).creationCode));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("CheckBalanceHigh already deployed at %s", preComputedAddress);
            save("CheckBalanceHigh", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            CheckBalanceHigh checkBalanceHigh = new CheckBalanceHigh{ salt: salt }();

            save("CheckBalanceHigh", address(checkBalanceHigh));
            console.log("CheckBalanceHigh deployed at %s", address(checkBalanceHigh));

            addr_ = address(checkBalanceHigh);
        }
    }

    /// @notice Deploy CheckGelatoLow contract.
    function deployCheckGelatoLow() public broadcast returns (address addr_) {
        bytes32 salt = keccak256(bytes("CheckGelatoLow"));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(CheckGelatoLow).creationCode));
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("CheckGelatoLow already deployed at %s", preComputedAddress);
            save("CheckGelatoLow", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            CheckGelatoLow checkGelatoLow = new CheckGelatoLow{ salt: salt }();

            save("CheckGelatoLow", address(checkGelatoLow));
            console.log("CheckGelatoLow deployed at %s", address(checkGelatoLow));

            addr_ = address(checkGelatoLow);
        }
    }

    /// @notice Initialize the Faucet
    function initializeFaucet() public broadcast {
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address faucetProxy = mustGetAddress("FaucetProxy");
        address faucet = mustGetAddress("Faucet");
        address implementationAddress = proxyAdmin.getProxyImplementation(faucetProxy);
        if (implementationAddress == faucet) {
            console.log("Faucet proxy implementation already set");
        } else {
            proxyAdmin.upgrade({ _proxy: payable(faucetProxy), _implementation: faucet });
        }

        require(Faucet(payable(faucetProxy)).ADMIN() == Faucet(payable(faucet)).ADMIN());
    }

    /// @notice installs the drip configs in the faucet drippie contract.
    function installFaucetDrippieConfigs() public {
        Drippie drippie = Drippie(mustGetAddress("FaucetDrippie"));
        console.log("Installing faucet drips at %s", address(drippie));
        installFaucetDripV1();
        installFaucetDripV2();
        installFaucetAdminDripV1();
        installFaucetGelatoBalanceV1();

        console.log("Faucet drip configs successfully installed");
    }

    /// @notice installs the FaucetDripV1 drip on the faucet drippie contract.
    function installFaucetDripV1() public broadcast {
        Drippie drippie = Drippie(mustGetAddress("FaucetDrippie"));
        string memory dripName = "FaucetDripV1";
        if (drippie.getDripStatus(dripName) == Drippie.DripStatus.NONE) {
            console.log("installing %s", dripName);
            Drippie.DripAction[] memory actions = new Drippie.DripAction[](1);
            actions[0] =
                Drippie.DripAction({ target: mustGetAddress("FaucetProxy"), data: "", value: cfg.faucetDripV1Value() });
            drippie.create({
                _name: dripName,
                _config: Drippie.DripConfig({
                    reentrant: false,
                    interval: cfg.faucetDripV1Interval(),
                    dripcheck: CheckBalanceLow(mustGetAddress("CheckBalanceLow")),
                    checkparams: abi.encode(
                        CheckBalanceLow.Params({ target: mustGetAddress("FaucetProxy"), threshold: cfg.faucetDripV1Threshold() })
                        ),
                    actions: actions
                })
            });
            console.log("%s installed successfully", dripName);
        } else {
            console.log("%s already installed.", dripName);
        }

        _activateIfPausedDrip(drippie, dripName);
    }

    /// @notice installs the FaucetDripV2 drip on the faucet drippie contract.
    function installFaucetDripV2() public broadcast {
        Drippie drippie = Drippie(mustGetAddress("FaucetDrippie"));
        string memory dripName = "FaucetDripV2";
        if (drippie.getDripStatus(dripName) == Drippie.DripStatus.NONE) {
            console.log("installing %s", dripName);
            Drippie.DripAction[] memory actions = new Drippie.DripAction[](1);
            actions[0] =
                Drippie.DripAction({ target: mustGetAddress("FaucetProxy"), data: "", value: cfg.faucetDripV2Value() });
            drippie.create({
                _name: dripName,
                _config: Drippie.DripConfig({
                    reentrant: false,
                    interval: cfg.faucetDripV2Interval(),
                    dripcheck: CheckBalanceLow(mustGetAddress("CheckBalanceLow")),
                    checkparams: abi.encode(
                        CheckBalanceLow.Params({ target: mustGetAddress("FaucetProxy"), threshold: cfg.faucetDripV2Threshold() })
                        ),
                    actions: actions
                })
            });
            console.log("%s installed successfully", dripName);
        } else {
            console.log("%s already installed.", dripName);
        }

        _activateIfPausedDrip(drippie, dripName);
    }

    /// @notice installs the FaucetAdminDripV1 drip on the faucet drippie contract.
    function installFaucetAdminDripV1() public broadcast {
        Drippie drippie = Drippie(mustGetAddress("FaucetDrippie"));
        string memory dripName = "FaucetAdminDripV1";
        if (drippie.getDripStatus(dripName) == Drippie.DripStatus.NONE) {
            console.log("installing %s", dripName);
            Drippie.DripAction[] memory actions = new Drippie.DripAction[](1);
            actions[0] = Drippie.DripAction({
                target: mustGetAddress("FaucetProxy"),
                data: "",
                value: cfg.faucetAdminDripV1Value()
            });
            drippie.create({
                _name: dripName,
                _config: Drippie.DripConfig({
                    reentrant: false,
                    interval: cfg.faucetAdminDripV1Interval(),
                    dripcheck: CheckBalanceLow(mustGetAddress("CheckBalanceLow")),
                    checkparams: abi.encode(
                        CheckBalanceLow.Params({
                            target: mustGetAddress("FaucetProxy"),
                            threshold: cfg.faucetAdminDripV1Threshold()
                        })
                        ),
                    actions: actions
                })
            });
            console.log("%s installed successfully", dripName);
        } else {
            console.log("%s already installed.", dripName);
        }

        _activateIfPausedDrip(drippie, dripName);
    }

    /// @notice installs the GelatoBalanceV1 drip on the faucet drippie contract.
    function installFaucetGelatoBalanceV1() public broadcast {
        Drippie drippie = Drippie(mustGetAddress("FaucetDrippie"));
        string memory dripName = "GelatoBalanceV2";
        if (drippie.getDripStatus(dripName) == Drippie.DripStatus.NONE) {
            console.log("installing %s", dripName);
            Drippie.DripAction[] memory actions = new Drippie.DripAction[](1);
            actions[0] = Drippie.DripAction({
                target: payable(cfg.faucetGelatoTreasury()),
                data: abi.encodeWithSignature(
                    "depositFunds(address,address,uint256)",
                    cfg.faucetGelatoRecipient(),
                    // Gelato represents ETH as 0xeeeee....eeeee
                    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
                    cfg.faucetGelatoBalanceV1Value()
                    ),
                value: cfg.faucetGelatoBalanceV1Value()
            });
            drippie.create({
                _name: dripName,
                _config: Drippie.DripConfig({
                    reentrant: false,
                    interval: cfg.faucetGelatoBalanceV1DripInterval(),
                    dripcheck: CheckGelatoLow(mustGetAddress("CheckGelatoLow")),
                    checkparams: abi.encode(
                        CheckGelatoLow.Params({
                            recipient: cfg.faucetGelatoRecipient(),
                            threshold: cfg.faucetGelatoThreshold(),
                            treasury: cfg.faucetGelatoTreasury()
                        })
                        ),
                    actions: actions
                })
            });
            console.log("%s installed successfully", dripName);
        } else {
            console.log("%s already installed.", dripName);
        }

        _activateIfPausedDrip(drippie, dripName);
    }

    function _activateIfPausedDrip(Drippie drippie, string memory dripName) internal {
        if (drippie.getDripStatus(dripName) == Drippie.DripStatus.PAUSED) {
            console.log("%s is paused, activating", dripName);
            drippie.status(dripName, Drippie.DripStatus.ACTIVE);
            console.log("%s activated", dripName);
            require(drippie.getDripStatus(dripName) == Drippie.DripStatus.ACTIVE);
        }
    }

    /// @notice deploys the On-Chain Authentication Module
    function deployOnChainAuthModule() public broadcast returns (address addr_) {
        string memory moduleName = "OnChainAuthModule";
        string memory version = "1";
        bytes32 salt = keccak256(bytes("OnChainAuthModule"));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(AdminFaucetAuthModule).creationCode,
                abi.encode(cfg.faucetOnchainAuthModuleAdmin(), moduleName, version)
            )
        );
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.log("OnChainAuthModule already deployed at %s", preComputedAddress);
            save("OnChainAuthModule", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            AdminFaucetAuthModule onChainAuthModule =
                new AdminFaucetAuthModule{ salt: salt }(cfg.faucetOnchainAuthModuleAdmin(), moduleName, version);
            require(onChainAuthModule.ADMIN() == cfg.faucetOnchainAuthModuleAdmin());

            save("OnChainAuthModule", address(onChainAuthModule));
            console.log("OnChainAuthModule deployed at %s", address(onChainAuthModule));

            addr_ = address(onChainAuthModule);
        }
    }

    /// @notice deploys the Off-Chain Authentication Module
    function deployOffChainAuthModule() public broadcast returns (address addr_) {
        string memory moduleName = "OffChainAuthModule";
        string memory version = "1";
        bytes32 salt = keccak256(bytes("OffChainAuthModule"));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(AdminFaucetAuthModule).creationCode,
                abi.encode(cfg.faucetOffchainAuthModuleAdmin(), moduleName, version)
            )
        );
        address preComputedAddress = computeCreate2Address(salt, initCodeHash);
        if (preComputedAddress.code.length > 0) {
            console.logBytes32(initCodeHash);
            console.log("OffChainAuthModule already deployed at %s", preComputedAddress);
            save("OffChainAuthModule", preComputedAddress);
            addr_ = preComputedAddress;
        } else {
            AdminFaucetAuthModule offChainAuthModule =
                new AdminFaucetAuthModule{ salt: salt }(cfg.faucetOffchainAuthModuleAdmin(), moduleName, version);
            require(offChainAuthModule.ADMIN() == cfg.faucetOffchainAuthModuleAdmin());

            save("OffChainAuthModule", address(offChainAuthModule));
            console.log("OffChainAuthModule deployed at %s", address(offChainAuthModule));

            addr_ = address(offChainAuthModule);
        }
    }

    /// @notice installs the OnChain AuthModule on the Faucet contract.
    function installOnChainAuthModule() public broadcast {
        string memory moduleName = "OnChainAuthModule";
        Faucet faucet = Faucet(mustGetAddress("Faucet"));
        AdminFaucetAuthModule onChainAuthModule = AdminFaucetAuthModule(mustGetAddress(moduleName));
        if (faucet.isModuleEnabled(onChainAuthModule)) {
            console.log("%s already installed.", moduleName);
        } else {
            console.log("Installing %s", moduleName);
            Faucet.ModuleConfig memory myModuleConfig = Faucet.ModuleConfig({
                name: moduleName,
                enabled: true,
                ttl: cfg.faucetOnchainAuthModuleTtl(),
                amount: cfg.faucetOnchainAuthModuleAmount()
            });
            faucet.configure(onChainAuthModule, myModuleConfig);
            console.log("%s installed successfully", moduleName);
        }
    }

    /// @notice installs the OffChain AuthModule on the Faucet contract.
    function installOffChainAuthModule() public broadcast {
        string memory moduleName = "OffChainAuthModule";
        Faucet faucet = Faucet(mustGetAddress("Faucet"));
        AdminFaucetAuthModule offChainAuthModule = AdminFaucetAuthModule(mustGetAddress(moduleName));
        if (faucet.isModuleEnabled(offChainAuthModule)) {
            console.log("%s already installed.", moduleName);
        } else {
            console.log("Installing %s", moduleName);
            Faucet.ModuleConfig memory myModuleConfig = Faucet.ModuleConfig({
                name: moduleName,
                enabled: true,
                ttl: cfg.faucetOffchainAuthModuleTtl(),
                amount: cfg.faucetOffchainAuthModuleAmount()
            });
            faucet.configure(offChainAuthModule, myModuleConfig);
            console.log("%s installed successfully", moduleName);
        }
    }

    /// @notice installs all of the auth module in the faucet contract.
    function installFaucetAuthModulesConfigs() public {
        Faucet faucet = Faucet(mustGetAddress("Faucet"));
        console.log("Installing auth modules at %s", address(faucet));
        installOnChainAuthModule();
        installOffChainAuthModule();

        console.log("Faucet Auth Module configs successfully installed");
    }
}
